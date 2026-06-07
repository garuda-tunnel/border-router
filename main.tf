locals {
  # Track own-chart template changes so the helm_release upgrades when the
  # deployment template, FRR configmap template, or entrypoint changes.
  template_checksum = sha256(join("", [
    filesha256("${path.module}/charts/border-router/templates/deployment.yaml"),
    filesha256("${path.module}/charts/border-router/templates/configmap-frr.yaml"),
    filesha256("${path.module}/image/entrypoint.sh"),
  ]))
}

resource "helm_release" "border_router" {
  name              = var.name
  namespace         = var.namespace
  create_namespace  = false
  chart             = "${path.module}/charts/border-router"
  dependency_update = true

  values = [
    yamlencode({
      namespace = var.namespace
      name      = var.name
      images = {
        border = var.image
        frr    = var.frr_image
      }
      ospf             = var.ospf
      templateChecksum = local.template_checksum
    })
  ]
}
