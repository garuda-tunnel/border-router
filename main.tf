locals {
  effective_mtu = var.mtu_policy.site_mtu != null ? var.mtu_policy.site_mtu : var.mtu_policy.effective_mtu
  fixed_mss     = var.mtu_policy.site_mtu != null ? var.mtu_policy.site_mtu - 40 : var.mtu_policy.fixed_mss
  # mss_clamp_enabled defaults to true via optional(bool, true) in the policy type.
  # Task 6 wires it to BR_MSS_CLAMP_ENABLED to gate the border_mss nft table install.
  mss_clamp_enabled = var.mtu_policy.mss_clamp_enabled

  # Empty/omitted keys ⇒ Helm coalesce preserves the chart-side images.* pinned
  # digests; a non-empty var overrides only that one key.
  # frr_image is DEPRECATED (frr-sidecar is now MAP-injected); kept as inert input.
  images_override = merge(
    var.image == "" ? {} : { border = var.image },
  )
}

resource "kubernetes_config_map" "garuda_extra" {
  for_each = var.configmaps
  metadata {
    name      = each.key
    namespace = var.namespace
  }
  # each.value is a { filename => content } map (Decision #11).
  data = each.value
}

resource "helm_release" "border_router" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = false

  # Consume the published chart from OCI by an exact pinned version.
  # Source stays in charts/border-router for release-please / CI / local dev.
  repository = "oci://ghcr.io/garuda-tunnel/charts"
  chart      = "border-router"
  version    = var.chart_version

  # No-op for the OCI path (dependency is vendored in the published tgz);
  # kept so the local-path dev/hotfix escape hatch still resolves chart deps.
  dependency_update = true

  values = [
    yamlencode({
      namespace      = var.namespace
      name           = var.name
      images         = local.images_override
      ospf           = var.ospf
      # podLabels/podAnnotations are rendered on spec.template.metadata only
      podLabels      = var.labels
      podAnnotations = var.annotations
      mtuPolicy = {
        fixedMss        = local.fixed_mss
        mssClampEnabled = local.mss_clamp_enabled
      }
    })
  ]

  depends_on = [kubernetes_config_map.garuda_extra]
}
