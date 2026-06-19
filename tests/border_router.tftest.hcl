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
  mtu_policy = {
    site_mtu = 1330
  }
}

run "chart_resolves_from_oci" {
  command = plan

  assert {
    condition     = helm_release.border_router.repository == "oci://ghcr.io/garuda-tunnel/charts"
    error_message = "helm_release.repository must be the garuda OCI charts registry"
  }
  assert {
    condition     = helm_release.border_router.chart == "border-router"
    error_message = "helm_release.chart must be the OCI chart name 'border-router'"
  }
  assert {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", helm_release.border_router.version))
    error_message = "helm_release.version must be an exact semver from var.chart_version"
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

run "empty_image_vars_omit_keys" {
  command = plan
  variables {
    namespace = "garuda"
    name      = "border-router"
    image     = ""
    frr_image = ""
    ospf = {
      router_id = "198.51.100.50"
    }
    mtu_policy = {
      site_mtu = 1330
    }
  }
  assert {
    condition     = !strcontains(helm_release.border_router.values[0], "garuda-border-router@sha256:")
    error_message = "images.border must be omitted when image var is empty (chart digest must win)"
  }
  assert {
    condition     = !strcontains(helm_release.border_router.values[0], "\"frr\":")
    error_message = "images.frr must be omitted when frr_image var is empty"
  }
}

run "mtu_policy_site_mtu_derives_values" {
  command = plan

  variables {
    mtu_policy = {
      site_mtu = 1330
    }
  }

  assert {
    condition     = local.effective_mtu == 1330
    error_message = "site_mtu must derive effective_mtu 1330"
  }

  assert {
    condition     = local.fixed_mss == 1290
    error_message = "site_mtu 1330 must derive fixed_mss 1290"
  }

  assert {
    condition     = strcontains(helm_release.border_router.values[0], "\"fixedMss\": 1290")
    error_message = "site_mtu 1330 must render mtuPolicy.fixedMss: 1290 in helm values"
  }

  assert {
    condition     = strcontains(helm_release.border_router.values[0], "\"mssClampEnabled\": true")
    error_message = "default mtu_policy must render mtuPolicy.mssClampEnabled: true in helm values"
  }
}

run "mtu_policy_explicit_override_honors_values" {
  # explicit override: effective_mtu=1380, fixed_mss=1340 must pass through unchanged.
  command = plan

  variables {
    mtu_policy = {
      effective_mtu = 1380
      fixed_mss     = 1340
    }
  }

  assert {
    condition     = local.effective_mtu == 1380
    error_message = "explicit effective_mtu=1380 must be honored"
  }

  assert {
    condition     = local.fixed_mss == 1340
    error_message = "explicit fixed_mss=1340 must be honored"
  }

  assert {
    condition     = strcontains(helm_release.border_router.values[0], "\"fixedMss\": 1340")
    error_message = "explicit fixed_mss=1340 must render mtuPolicy.fixedMss: 1340 in helm values"
  }
}

run "mtu_policy_clamp_disabled" {
  # mss_clamp_enabled=false must render mtuPolicy.mssClampEnabled: false.
  command = plan

  variables {
    mtu_policy = {
      site_mtu          = 1330
      mss_clamp_enabled = false
    }
  }

  assert {
    condition     = strcontains(helm_release.border_router.values[0], "\"mssClampEnabled\": false")
    error_message = "mss_clamp_enabled=false must render mtuPolicy.mssClampEnabled: false"
  }
}

run "mtu_policy_reject_xor_violation" {
  # Passing both site_mtu and effective_mtu violates the XOR constraint.
  command = plan

  variables {
    mtu_policy = {
      site_mtu      = 1330
      effective_mtu = 1280
    }
  }

  expect_failures = [var.mtu_policy]
}

run "nonempty_image_overrides" {
  command = plan
  variables {
    namespace = "garuda"
    name      = "border-router"
    image     = "ghcr.io/garuda-tunnel/garuda-border-router@sha256:1111111111111111111111111111111111111111111111111111111111111111"
    frr_image = ""
    ospf = {
      router_id = "198.51.100.50"
    }
    mtu_policy = {
      site_mtu = 1330
    }
  }
  assert {
    condition     = strcontains(helm_release.border_router.values[0], "garuda-border-router@sha256:1111111111111111111111111111111111111111111111111111111111111111")
    error_message = "images.border must carry the override digest when image var is non-empty"
  }
  assert {
    condition     = !strcontains(helm_release.border_router.values[0], "\"frr\":")
    error_message = "images.frr must be omitted when frr_image var is empty"
  }
}
