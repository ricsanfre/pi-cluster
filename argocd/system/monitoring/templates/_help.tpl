{{/* Set kube-prometheus stack name */}}
{{- define "monitoring-stack.name" -}}
  {{- if index .Values "kube-prometheus-stack.fullnameOverride"  -}}
    {{- index .Values "kube-prometheus-stack.fullnameOverride" -}}
  {{- else -}}
    {{- .Release.Name -}}
  {{- end -}}
{{- end -}}