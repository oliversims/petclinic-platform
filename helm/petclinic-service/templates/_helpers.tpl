{{/*
=============================================================================
helm/petclinic-service/templates/_helpers.tpl
Purpose: Shared name, label, and replica logic so no template repeats it.
=============================================================================
*/}}

{{/* Service name. Falls back to the release name when values set none. */}}
{{- define "petclinic-service.name" -}}
{{- default .Release.Name .Values.name -}}
{{- end -}}

{{/* Labels on every resource. */}}
{{- define "petclinic-service.labels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.name" . }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: {{ .Values.component }}
{{- end -}}

{{/* Selector: name only, so labels can change without orphaning pods. */}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.name" . }}
{{- end -}}

{{/*
Replica count. replicaOverrides[name] wins when set, otherwise replicaCount.
Lets prod run replicaCount: 2 while GenAI and Admin stay at 1.
*/}}
{{- define "petclinic-service.replicas" -}}
{{- $name := include "petclinic-service.name" . -}}
{{- if hasKey .Values.replicaOverrides $name -}}
{{- index .Values.replicaOverrides $name -}}
{{- else -}}
{{- .Values.replicaCount -}}
{{- end -}}
{{- end -}}

{{/* Full image reference. */}}
{{- define "petclinic-service.image" -}}
{{ .Values.image.registry }}/{{ .Values.image.name }}:{{ .Values.image.tag }}
{{- end -}}
