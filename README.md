# AuthGate Helm Chart

> Helm chart for deploying [AuthGate](https://github.com/go-authgate/authgate) — a lightweight OAuth 2.0 Authorization Server supporting Device Flow (RFC 8628), Authorization Code Flow with PKCE (RFC 7636), and Client Credentials Grant.

## Features

- **Single-instance mode** — SQLite with persistent volume, zero external dependencies
- **High-availability mode** — PostgreSQL + Redis for multi-replica deployments
- **Built-in subchart support** — Optional [bitnami/postgresql](https://github.com/bitnami/charts/tree/main/bitnami/postgresql) and [bitnami/redis](https://github.com/bitnami/charts/tree/main/bitnami/redis) for one-click dev/test setup
- **Security hardened** — Non-root container (UID 1000), read-only root filesystem, dropped capabilities
- **Metrics leader election** — Dedicated single-replica pod for gauge updates in multi-replica mode
- **Prometheus integration** — ServiceMonitor for Prometheus Operator
- **Ingress, HPA, PDB** — Production-ready Kubernetes resources
- **External secret support** — Use existing Kubernetes Secrets (Vault, External Secrets Operator, Sealed Secrets)

## Prerequisites

- Kubernetes 1.26+
- Helm 3.10+

## Quick Start

### Install from source

```bash
git clone https://github.com/go-authgate/helm-authgate.git
cd helm-authgate
helm dependency update .
```

### Minimal installation (SQLite)

```bash
helm install authgate . \
  --set secrets.jwtSecret="$(openssl rand -hex 32)" \
  --set secrets.sessionSecret="$(openssl rand -hex 32)" \
  --set server.baseUrl="https://auth.example.com"
```

### Access the service

```bash
kubectl port-forward svc/authgate 8080:80
# Visit http://localhost:8080
```

## Configuration

All configuration is done through `values.yaml`. Key sections:

### Core Settings

| Parameter            | Description                                   | Default                        |
| -------------------- | --------------------------------------------- | ------------------------------ |
| `replicaCount`       | Number of replicas (must be 1 for SQLite)     | `1`                            |
| `image.repository`   | Container image                               | `ghcr.io/go-authgate/authgate` |
| `image.tag`          | Image tag (defaults to chart appVersion)      | `""`                           |
| `server.baseUrl`     | Public URL for OAuth redirects (**required**) | `""`                           |
| `server.environment` | `production` or `development`                 | `"production"`                 |

### Database

| Parameter               | Description                | Default    |
| ----------------------- | -------------------------- | ---------- |
| `database.driver`       | `sqlite` or `postgres`     | `"sqlite"` |
| `persistence.enabled`   | Enable PVC for SQLite      | `true`     |
| `persistence.size`      | PVC size                   | `1Gi`      |
| `externalDatabase.host` | External PostgreSQL host   | `""`       |
| `postgresql.enabled`    | Deploy PostgreSQL subchart | `false`    |

### Secrets

| Parameter                      | Description                                 | Default |
| ------------------------------ | ------------------------------------------- | ------- |
| `secrets.existingSecret`       | Use pre-created Secret                      | `""`    |
| `secrets.jwtSecret`            | JWT signing secret (**required** for HS256) | `""`    |
| `secrets.sessionSecret`        | Session encryption secret (**required**)    | `""`    |
| `secrets.defaultAdminPassword` | Admin password (random if empty)            | `""`    |

### Redis

| Parameter            | Description            | Default    |
| -------------------- | ---------------------- | ---------- |
| `redis.enabled`      | Deploy Redis subchart  | `false`    |
| `externalRedis.addr` | External Redis address | `""`       |
| `rateLimit.store`    | `memory` or `redis`    | `"memory"` |

### Metrics & Monitoring

| Parameter                        | Description                         | Default          |
| -------------------------------- | ----------------------------------- | ---------------- |
| `metrics.enabled`                | Enable Prometheus /metrics endpoint | `false`          |
| `metrics.serviceMonitor.enabled` | Create ServiceMonitor               | `false`          |
| `metricsLeader.strategy`         | Multi-replica gauge strategy        | `"env-override"` |

### Ingress

| Parameter           | Description             | Default |
| ------------------- | ----------------------- | ------- |
| `ingress.enabled`   | Enable Ingress          | `false` |
| `ingress.className` | Ingress class name      | `""`    |
| `ingress.hosts`     | List of hosts and paths | `[]`    |
| `ingress.tls`       | TLS configuration       | `[]`    |

For the complete list of parameters, see [`values.yaml`](values.yaml).

## Deployment Modes

### SQLite (Single Instance)

Best for development, testing, or low-traffic deployments:

```yaml
# values-sqlite.yaml
replicaCount: 1
database:
  driver: sqlite
persistence:
  enabled: true
  size: 1Gi
secrets:
  jwtSecret: "your-jwt-secret"
  sessionSecret: "your-session-secret"
server:
  baseUrl: "https://auth.example.com"
```

```bash
helm install authgate . -f values-sqlite.yaml
```

### PostgreSQL + Redis (High Availability)

For production multi-replica deployments with external databases:

```yaml
# Example: HA with external databases
replicaCount: 3
database:
  driver: postgres
externalDatabase:
  host: "postgres.example.com"
  user: "authgate"
  password: "secret"
  database: "authgate"
externalRedis:
  addr: "redis.example.com:6379"
rateLimit:
  store: redis
cache:
  user:
    type: redis
  token:
    enabled: true
    type: redis
metrics:
  enabled: true
secrets:
  jwtSecret: "your-jwt-secret"
  sessionSecret: "your-session-secret"
server:
  baseUrl: "https://auth.example.com"
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: auth.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: auth-tls
      hosts:
        - auth.example.com
```

```bash
helm install authgate . -f values-ha-external.yaml
```

### PostgreSQL + Redis (Subchart for Dev/Test)

One-click setup with bundled PostgreSQL and Redis:

```yaml
# Example: HA with bundled subcharts
replicaCount: 2
database:
  driver: postgres
postgresql:
  enabled: true
  auth:
    database: authgate
    username: authgate
    password: "pg-password"
redis:
  enabled: true
  architecture: standalone
  auth:
    enabled: true
    password: "redis-password"
rateLimit:
  store: redis
secrets:
  jwtSecret: "your-jwt-secret"
  sessionSecret: "your-session-secret"
server:
  baseUrl: "http://localhost:8080"
```

```bash
helm dependency update .
helm install authgate . -f values-ha-subchart.yaml
```

## Using Existing Secrets

For production, create a Secret externally (e.g., via Vault, Sealed Secrets) and reference it:

```yaml
secrets:
  existingSecret: "authgate-secrets"
```

The Secret must contain these keys:

| Key                      | Required                  | Description                            |
| ------------------------ | ------------------------- | -------------------------------------- |
| `JWT_SECRET`             | Yes (HS256)               | JWT signing secret                     |
| `JWT_PRIVATE_KEY_PEM`    | When using RS256/ES256    | Inline PEM private key for JWT signing |
| `SESSION_SECRET`         | Yes                       | Session encryption secret              |
| `DATABASE_DSN`           | When using postgres       | PostgreSQL connection string           |
| `REDIS_PASSWORD`         | When using external Redis | Redis password                         |
| `DEFAULT_ADMIN_PASSWORD` | No                        | Admin user password                    |

## Testing Locally with colima (macOS)

[Colima](https://github.com/abiosoft/colima) provides a lightweight local Kubernetes environment using k3s on macOS:

```bash
# Start a k3s cluster (2 CPU, 4GB RAM, 60GB disk)
colima start --kubernetes --cpu 2 --memory 4 --disk 60

# Verify
kubectl get nodes

# Install (single-instance with PostgreSQL subchart)
helm dependency update .
helm install authgate . -f ci/values-single-postgres.yaml \
  --namespace authgate --create-namespace --wait

# Health check
kubectl -n authgate exec deploy/authgate -- wget -qO- http://localhost:8080/health

# Access via port-forward
kubectl -n authgate port-forward svc/authgate 8088:80                    # AuthGate:    http://localhost:8088
kubectl -n authgate port-forward svc/authgate-postgresql 5433:5432       # PostgreSQL:  localhost:5433
kubectl -n authgate port-forward svc/authgate-ha-redis-master 6380:6379  # Redis:       localhost:6380 (HA mode only)

# Clean up
helm uninstall authgate -n authgate
colima stop
```

## Testing Locally with k3d

A test script is provided to spin up a local k3d cluster and validate both deployment modes:

```bash
# Prerequisites: docker, k3d, helm, kubectl
# Install k3d: brew install k3d

# Run the full test suite
bash ci/test-local.sh
```

The script will:

1. Create a k3d cluster (`authgate-test`)
2. Test SQLite single-instance mode
3. Test HA mode with PostgreSQL + Redis subcharts
4. Clean up the cluster

You can also test individual modes:

```bash
# SQLite only
helm install authgate-test . -f ci/values-sqlite.yaml --wait

# HA only
helm dependency update .
helm install authgate-test . -f ci/values-ha.yaml --wait
```

## Static Validation

Validate templates without a cluster:

```bash
# Lint
helm lint .

# Render default (SQLite)
helm template test .

# Render HA mode
helm template test . \
  --set database.driver=postgres \
  --set replicaCount=3 \
  --set externalDatabase.host=pg \
  --set externalRedis.addr=redis:6379

# Verify SQLite + multi-replica fails
helm template test . --set replicaCount=2 --set database.driver=sqlite
# Expected: error about SQLite not supporting concurrent access
```

## Uninstall

```bash
helm uninstall authgate

# If using SQLite, clean up the PVC
kubectl delete pvc -l app.kubernetes.io/instance=authgate
```

## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/go-authgate/authgate/blob/main/LICENSE) file in the main AuthGate repository.
