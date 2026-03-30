#!/usr/bin/env bash
set -euo pipefail

# AuthGate Helm Chart - Local k3d Test Script
# Creates a k3d cluster, runs SQLite and HA tests, then cleans up.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="authgate-test"
NAMESPACE="authgate-test"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

cleanup() {
  info "Cleaning up..."
  k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
}

check_prerequisites() {
  local missing=()
  for cmd in docker k3d helm kubectl; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    error "Missing required tools: ${missing[*]}"
    echo "Install them first:"
    echo "  brew install k3d helm kubectl"
    exit 1
  fi
  if ! docker info &>/dev/null; then
    error "Docker is not running. Please start Docker first."
    exit 1
  fi
  info "All prerequisites satisfied."
}

create_cluster() {
  if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    warn "Cluster '$CLUSTER_NAME' already exists. Deleting..."
    k3d cluster delete "$CLUSTER_NAME"
  fi
  info "Creating k3d cluster '$CLUSTER_NAME'..."
  k3d cluster create "$CLUSTER_NAME" \
    -p "8080:80@loadbalancer" \
    --wait
  kubectl create namespace "$NAMESPACE" || true
  info "Cluster ready."
}

update_deps() {
  info "Updating Helm dependencies..."
  helm dependency update "$CHART_DIR"
}

wait_for_pods() {
  local label="$1"
  local timeout="${2:-180s}"
  info "Waiting for pods ($label) to be ready (timeout: $timeout)..."
  kubectl wait --namespace "$NAMESPACE" \
    --for=condition=ready pod \
    -l "$label" \
    --timeout="$timeout"
}

test_health() {
  local svc="$1"
  info "Testing /health endpoint..."
  kubectl run --namespace "$NAMESPACE" health-check --rm -i --restart=Never \
    --image=busybox:1.36 -- \
    wget --no-verbose --tries=3 --spider "http://${svc}/health"
  info "/health check passed."
}

# ============================================================
# Test 1: SQLite single instance
# ============================================================
test_sqlite() {
  info "========================================="
  info "Test 1: SQLite single-instance mode"
  info "========================================="

  helm install authgate-sqlite "$CHART_DIR" \
    --namespace "$NAMESPACE" \
    -f "$CHART_DIR/ci/values-sqlite.yaml" \
    --wait --timeout 120s

  wait_for_pods "app.kubernetes.io/name=authgate"
  test_health "authgate-sqlite-authgate:80"

  info "Running helm test..."
  helm test authgate-sqlite --namespace "$NAMESPACE" --timeout 60s

  info "SQLite test PASSED. Cleaning up release..."
  helm uninstall authgate-sqlite --namespace "$NAMESPACE" --wait
  # Wait for PVC cleanup
  kubectl delete pvc --namespace "$NAMESPACE" -l app.kubernetes.io/instance=authgate-sqlite --ignore-not-found
}

# ============================================================
# Test 2: HA mode (PostgreSQL + Redis)
# ============================================================
test_ha() {
  info "========================================="
  info "Test 2: HA mode (PostgreSQL + Redis)"
  info "========================================="

  helm install authgate-ha "$CHART_DIR" \
    --namespace "$NAMESPACE" \
    -f "$CHART_DIR/ci/values-ha.yaml" \
    --wait --timeout 300s

  info "Waiting for PostgreSQL..."
  wait_for_pods "app.kubernetes.io/name=postgresql" "180s"

  info "Waiting for Redis..."
  wait_for_pods "app.kubernetes.io/name=redis" "120s"

  info "Waiting for AuthGate pods..."
  wait_for_pods "app.kubernetes.io/name=authgate" "180s"

  # Verify replica count
  local ready
  ready=$(kubectl get deploy --namespace "$NAMESPACE" authgate-ha-authgate -o jsonpath='{.status.readyReplicas}')
  if [ "$ready" -ge 2 ]; then
    info "HA replicas running: $ready"
  else
    error "Expected 2+ replicas, got: $ready"
    exit 1
  fi

  # Verify metrics leader
  local leader_ready
  leader_ready=$(kubectl get deploy --namespace "$NAMESPACE" authgate-ha-authgate-metrics-leader -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "$leader_ready" -ge 1 ]; then
    info "Metrics leader pod running."
  else
    warn "Metrics leader pod not ready (may be expected if metrics subchart not yet up)."
  fi

  test_health "authgate-ha-authgate:80"

  info "Running helm test..."
  helm test authgate-ha --namespace "$NAMESPACE" --timeout 60s

  info "HA test PASSED. Cleaning up release..."
  helm uninstall authgate-ha --namespace "$NAMESPACE" --wait
}

# ============================================================
# Main
# ============================================================
main() {
  trap cleanup EXIT

  check_prerequisites
  create_cluster
  update_deps

  test_sqlite
  test_ha

  echo ""
  info "========================================="
  info "All tests PASSED!"
  info "========================================="
}

main "$@"
