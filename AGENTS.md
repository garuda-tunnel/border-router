# AGENTS.md

Security and contribution rules for garuda-border-router.

## Security

- Never commit or use real public IP addresses. Use RFC5737 (TEST-NET) / RFC1918 / CGNAT ranges only.
- Never commit or use domains other than well-known examples or `example.net`.
- Never commit secrets, tokens, private keys, or customer data.

## Garuda platform rules

This repo is part of garuda-tunnel. Platform rules (annotation-layer design, MAP/VAP
injection engine, `garuda_guest` contract, vanilla guest contract, bootstrap timing,
Multus attach-race fix, anti-patterns):

**See: https://github.com/garuda-tunnel/garuda/blob/main/docs/AGENTS-platform.md**
Local path: `../garuda/docs/AGENTS-platform.md`

## Layout

This repo's Terraform files are at the repo root (no `kube/` subdir). Consume via:

    source = "git::https://github.com/garuda-tunnel/garuda-border-router.git?ref=vX.Y.Z"

with **no** `//subdir` suffix. The TF source ref is:

    git::https://github.com/garuda-tunnel/garuda-border-router.git?ref=vX.Y.Z

## Border-router-specific notes

- **`egress-setup` is a one-shot init container** (NOT a native sidecar): dummy0 `/32`
  router-id materialisation, border_egress RPDB table (102), nft masquerade on border,
  MSS clamp. It MUST NOT have `restartPolicy: Always`. The MAP injects the `frr-sidecar`
  native sidecar separately; `egress-setup` is border-router's own workload-native fabric
  function and stays in this chart.
- `NET_ADMIN` in `egress-setup` is workload-native (border routing fabric). NOT injected
  by garuda.
- This module is a **vanilla guest**: accepts `annotations`, `labels`, `configmaps` map
  inputs and has zero garuda knowledge. See platform rules for the full contract.
