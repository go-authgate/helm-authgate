{{/*
Expand the name of the chart.
*/}}
{{- define "authgate.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "authgate.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "authgate.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "authgate.labels" -}}
helm.sh/chart: {{ include "authgate.chart" . }}
{{ include "authgate.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "authgate.selectorLabels" -}}
app.kubernetes.io/name: {{ include "authgate.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "authgate.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "authgate.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the secret name to use
*/}}
{{- define "authgate.secretName" -}}
{{- if .Values.secrets.existingSecret }}
{{- .Values.secrets.existingSecret }}
{{- else }}
{{- include "authgate.fullname" . }}
{{- end }}
{{- end }}

{{/*
Return the configmap name
*/}}
{{- define "authgate.configMapName" -}}
{{- include "authgate.fullname" . }}-config
{{- end }}

{{/*
Return the Redis address.
If redis subchart is enabled, use the subchart service name.
Otherwise, use externalRedis.addr.
*/}}
{{- define "authgate.redisAddr" -}}
{{- if .Values.redis.enabled }}
{{- printf "%s-redis-master:6379" .Release.Name }}
{{- else }}
{{- .Values.externalRedis.addr }}
{{- end }}
{{- end }}

{{/*
Return the Redis password secret key reference.
*/}}
{{- define "authgate.redisPasswordSecretKey" -}}
{{- if .Values.redis.enabled }}
redis-password
{{- else }}
REDIS_PASSWORD
{{- end }}
{{- end }}

{{/*
Return the PostgreSQL DSN.
If postgresql subchart is enabled, construct from subchart values.
Otherwise, use secrets.databaseDsn or construct from externalDatabase.
*/}}
{{- define "authgate.postgresDsn" -}}
{{- if .Values.postgresql.enabled }}
{{- printf "host=%s-postgresql user=%s password=%s dbname=%s port=5432 sslmode=disable" .Release.Name .Values.postgresql.auth.username .Values.postgresql.auth.password .Values.postgresql.auth.database }}
{{- else if .Values.secrets.databaseDsn }}
{{- .Values.secrets.databaseDsn }}
{{- else }}
{{- printf "host=%s user=%s password=%s dbname=%s port=%d sslmode=%s" .Values.externalDatabase.host .Values.externalDatabase.user .Values.externalDatabase.password .Values.externalDatabase.database (.Values.externalDatabase.port | int) .Values.externalDatabase.sslmode }}
{{- end }}
{{- end }}

{{/*
Determine if Redis is available (either subchart or external).
*/}}
{{- define "authgate.redisAvailable" -}}
{{- if or .Values.redis.enabled (ne .Values.externalRedis.addr "") }}true{{- end }}
{{- end }}
