variable "namespace" {
  description = "Existing Kubernetes namespace, sourced from module.garuda_k8s.namespace."
  type        = string
}

variable "name" {
  description = "Deployment name."
  type        = string
  default     = "border-router"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid DNS-1123 label."
  }
}

variable "image" {
  description = "egress-setup image (component-local garuda-border-router build). Empty ⇒ use the chart's pinned digest."
  type        = string
  default     = ""
}

variable "frr_image" {
  description = "Image reference for the frr-sidecar container. Empty ⇒ use the frr-sidecar library default digest (REQUIRES the frr-sidecar library-default task to have shipped; until then callers must pass a non-empty frr_image or the rendered frr container will fail to pull)."
  type        = string
  default     = ""
}

variable "chart_version" {
  description = "Pinned OCI chart version (exact semver). Bumped in lockstep with Chart.yaml by release-please."
  type        = string
  default     = "0.2.0" # x-release-please-version

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.chart_version))
    error_message = "chart_version must be exact semver MAJOR.MINOR.PATCH (no range, no 'latest')."
  }
}

variable "ospf" {
  description = <<EOT
OSPF intent. The single `router_id` IPv4 is materialised as the dummy0 /32 and
advertised, so it is also the ingress nexthop ipt_server targets
(gw=<router_id>). The interface list (backbone + dummy0) and passive-interface
and transit_provider=false invariants are injected by the chart, not exposed
here.
EOT
  type = object({
    router_id = string
  })

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.ospf.router_id))
    error_message = "ospf.router_id must be an IPv4-formatted string."
  }
}
