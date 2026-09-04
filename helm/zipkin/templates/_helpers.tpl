{{/*
=============================================================================
helm/zipkin/templates/_helpers.tpl
Purpose: Shared name and label helpers.
=============================================================================
*/}}

{{- define "zipkin.name" -}}
{{- default .Release.Name .Values.nameOverride -}}
{{- end -}}

{{- define "zipkin.labels" -}}
app.kubernetes.io/name: {{ include "zipkin.name" . }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: tracing
{{- end -}}

{{- define "zipkin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zipkin.name" . }}
{{- end -}}
