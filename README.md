# garuda-border-router

Terraform module + Helm chart + image for the border router (edge egress with egress-setup init container) in the Garuda topology.

The frr-sidecar is injected at admission by the garuda MAP (`garuda-inject-fabric`), not by this chart.

## Layout note

Unlike the other garuda-* component repos, **this repo's Terraform files are at the repo root** (no `kube/` subdir). Consume via:

    source = "git::https://github.com/garuda-tunnel/garuda-border-router.git?ref=vX.Y.Z"

with **no** `//subdir` suffix.

- Helm chart: `oci://ghcr.io/garuda-tunnel/charts/border-router` (published on tag push).
- Image: `ghcr.io/garuda-tunnel/garuda-border-router` (semver + `:latest` + `:sha-...`).

## Vanilla guest contract

This module accepts `annotations`, `labels`, and `configmaps` inputs from `garuda_guest` and has zero garuda knowledge. See `AGENTS.md` for details.

## Inputs

| Name | Description | Required |
|------|-------------|----------|
| `namespace` | Kubernetes namespace | yes |
| `name` | Deployment name | no (default: `border-router`) |
| `image` | egress-setup image override. Empty → chart-pinned digest | no |
| `frr_image` | **Deprecated.** frr-sidecar is MAP-injected; this variable is inert | no |
| `chart_version` | Pinned OCI chart semver | no (default: `1.1.0`) |
| `ospf` | OSPF intent object with `router_id`. Required for egress-setup | yes |
| `mtu_policy` | MTU/MSS policy (site_mtu or effective_mtu+fixed_mss) | yes |
| `annotations` | Pod-template annotations from `garuda_guest.annotations` | no |
| `labels` | Pod-template labels from `garuda_guest.labels` | no |
| `configmaps` | Extra ConfigMaps (Tier 2/3 FRR snippets) from `garuda_guest.configmaps` | no |
