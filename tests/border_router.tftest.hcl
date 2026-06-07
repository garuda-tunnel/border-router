# Validates: modules/border_router wires the helm_release at the bundled chart
#            with the single router_id input materialised into the chart values.
# Code:      modules/border_router/main.tf, variables.tf, outputs.tf
# Assertion: chart path resolves to charts/border-router; rendered values carry
#            name/namespace/images/ospf.router_id; invalid router_id is rejected.
# Method:    tofu test with mock helm/kubernetes providers (command = plan).
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  namespace = "garuda"
  name      = "border-router"
  image     = "ghcr.io/alexmkx/garuda-border-router:latest"
  frr_image = "ghcr.io/alexmkx/garuda-frr-sidecar:latest"
  ospf = {
    router_id = "198.51.100.50"
  }
}

run "chart_path_resolves_to_bundled_chart" {
  command = plan
  assert {
    condition     = endswith(helm_release.border_router.chart, "/charts/border-router")
    error_message = "helm_release.border_router.chart must point at $${path.module}/charts/border-router"
  }
}

run "values_carry_identity_and_images" {
  command = plan
  assert {
    condition     = strcontains(helm_release.border_router.values[0], "\"name\": \"border-router\"")
    error_message = "rendered values must include name"
  }
  assert {
    condition     = strcontains(helm_release.border_router.values[0], "\"border\": \"ghcr.io/alexmkx/garuda-border-router:latest\"")
    error_message = "rendered values must include the border-router image"
  }
  assert {
    condition     = strcontains(helm_release.border_router.values[0], "\"frr\": \"ghcr.io/alexmkx/garuda-frr-sidecar:latest\"")
    error_message = "rendered values must include the frr image"
  }
}

run "values_carry_router_id" {
  command = plan
  assert {
    condition     = strcontains(helm_release.border_router.values[0], "\"router_id\": \"198.51.100.50\"")
    error_message = "rendered values must carry ospf.router_id"
  }
}

run "output_deployment_name" {
  command = plan
  assert {
    condition     = output.deployment_name == "border-router"
    error_message = "output.deployment_name must equal var.name"
  }
}

run "reject_invalid_router_id" {
  command = plan
  variables {
    ospf = { router_id = "not-an-ip" }
  }
  expect_failures = [var.ospf]
}
