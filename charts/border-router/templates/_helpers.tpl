{{- define "borderRouter.labels" -}}
app.kubernetes.io/name: border-router
app.kubernetes.io/instance: {{ .Values.name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
garuda.managed-by: helm
{{- end -}}

{{- define "borderRouter.selector" -}}
app.kubernetes.io/name: border-router
app.kubernetes.io/instance: {{ .Values.name | quote }}
{{- end -}}

{{/*
Comma-separated Multus annotation. border_router always attaches both backbone
(OSPF transit + ingress) and border (egress). dummy0 is internal (no NAD).
*/}}
{{- define "borderRouter.networks" -}}
backbone@backbone,border@border
{{- end -}}

{{/*
Build the OSPF dict passed to the frr-sidecar library chart. The caller supplies
only router_id; the chart injects the interface invariants:
  interfaces        = [backbone, dummy0]   (advertise both)
  passive_interfaces = [dummy0]            (no neighbours on dummy0; still
                                            injected into the Router LSA so the
                                            /32 is reachable area-wide)
  transit_provider  = false                (border_router is not a provider)
*/}}
{{- define "borderRouter.ospf" -}}
{{- mergeOverwrite (deepCopy .Values.ospf) (dict
      "interfaces" (list "backbone" "dummy0")
      "passive_interfaces" (list "dummy0")
      "transit_provider" false
    ) | toJson -}}
{{- end -}}
