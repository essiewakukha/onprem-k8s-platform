{{/* Chart name, truncated to the 63-char DNS label limit. */}}
{{- define "notes-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name. */}}
{{- define "notes-api.fullname" -}}
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

{{- define "notes-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Selector labels: never change these after first install. */}}
{{- define "notes-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "notes-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "notes-api.labels" -}}
helm.sh/chart: {{ include "notes-api.chart" . }}
{{ include "notes-api.selectorLabels" . }}
app.kubernetes.io/version: {{ include "notes-api.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: k8s-platform
{{- end }}

{{- define "notes-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "notes-api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "notes-api.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag | toString | trunc 63 }}
{{- end }}

{{/* repository@digest when a digest is pinned, otherwise repository:tag. */}}
{{- define "notes-api.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (include "notes-api.imageTag" .) }}
{{- end }}
{{- end }}

{{- define "notes-api.claimName" -}}
{{- default (printf "%s-data" (include "notes-api.fullname" .)) .Values.persistence.existingClaim }}
{{- end }}

{{/* Fail fast on configurations that cannot survive a node failure. */}}
{{- define "notes-api.validate" -}}
{{- if and .Values.persistence.enabled (eq .Values.persistence.accessMode "ReadWriteOnce") (gt (int .Values.replicaCount) 1) }}
{{- fail "persistence.accessMode=ReadWriteOnce cannot be shared by more than one replica. Use ReadWriteMany or replicaCount=1." }}
{{- end }}
{{- if and (eq (int .Values.rollout.maxSurge) 0) (eq (int .Values.rollout.maxUnavailable) 0) }}
{{- fail "rollout.maxSurge and rollout.maxUnavailable cannot both be 0." }}
{{- end }}
{{- end }}