locals {
  # Empty/omitted keys ⇒ Helm coalesce preserves the chart-side images.* pinned
  # digests; a non-empty var overrides only that one key.
  images_override = merge(
    var.image == "" ? {} : { border = var.image },
    var.frr_image == "" ? {} : { frr = var.frr_image },
  )
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
  # kept so the local-path dev/hotfix escape hatch still resolves frr-sidecar.
  dependency_update = true

  values = [
    yamlencode({
      namespace = var.namespace
      name      = var.name
      images    = local.images_override
      ospf      = var.ospf
    })
  ]
}
