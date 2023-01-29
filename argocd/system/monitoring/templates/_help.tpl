{{/* Set kube-prometheus stack name */}}
{{- define "monitoring-stack.name" -}}
  {{- if index .Values "kube-prometheus-stack" -}}
    {{- $stack:= index .Values "kube-prometheus-stack" }}
    {{- $stack.fullnameOverride }}
  {{- else -}}
    {{- .Release.Name -}}
  {{- end -}}
{{- end -}}