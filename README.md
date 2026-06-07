# garuda-border-router

Terraform module + Helm chart + image for the border router (edge egress with FRR/OSPF) in the Garuda topology.

## Layout note

Unlike the other garuda-* component repos, **this repo's Terraform files are at the repo root** (no `kube/` subdir). Consume via:

    source = "git::https://github.com/garuda-tunnel/garuda-border-router.git?ref=vX.Y.Z"

with **no** `//subdir` suffix.

- Helm chart: `oci://ghcr.io/garuda-tunnel/charts/border-router` (published on tag push).
- Image: `ghcr.io/garuda-tunnel/garuda-border-router` (semver + `:latest` + `:sha-...`).

See `AGENTS.md` for the FRR-sidecar reuse rule.
