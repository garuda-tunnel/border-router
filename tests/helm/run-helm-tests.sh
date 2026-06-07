#!/usr/bin/env bash
# Helm-level tests for modules/border_router.
# Validates: the rendered chart contains the egress-setup initContainer, Pod
#            sysctls, the frr-sidecar container, and an frr.conf that advertises
#            dummy0 /32 as a passive interface in interface-mode OSPF.
# Code:      modules/border_router/charts/border-router/templates/*
# Assertion: helm lint passes; helm template matches tests/golden/default.yaml.
# Method:    helm dependency update + lint + template diff against golden.
# Update goldens with: REGEN_GOLDEN=1 ./run-helm-tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/../.."
CHART_DIR="${MODULE_DIR}/charts/border-router"
GOLDEN_DIR="${SCRIPT_DIR}/../golden"

helm dependency update "${CHART_DIR}"

for scenario in default; do
  values_file="${SCRIPT_DIR}/values-${scenario}.yaml"
  helm lint "${CHART_DIR}" -f "${values_file}"

  out="$(helm template border-router "${CHART_DIR}" --namespace garuda -f "${values_file}")"
  golden="${GOLDEN_DIR}/${scenario}.yaml"

  if [[ "${REGEN_GOLDEN:-0}" == "1" ]]; then
    printf '%s\n' "${out}" > "${golden}"
    echo "regenerated ${golden}"
    continue
  fi

  if ! diff -u "${golden}" <(printf '%s\n' "${out}"); then
    echo "golden mismatch for ${scenario}" >&2
    exit 1
  fi
  echo "ok: ${scenario}"
done
