{{- define "borderRouter.labels" -}}
app.kubernetes.io/name: border-router
app.kubernetes.io/instance: {{ .Values.name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: garuda
garuda.managed-by: helm
{{- end -}}

{{- define "borderRouter.selector" -}}
app.kubernetes.io/name: border-router
app.kubernetes.io/instance: {{ .Values.name | quote }}
{{- end -}}
