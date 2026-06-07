#!/usr/bin/env bash
# Validates: modules/border_router/image/entrypoint.sh programs the pod netns
#            (dummy0, border_egress RPDB, masquerade) and fails fast when the
#            border interface never appears.
# Code:      modules/border_router/image/entrypoint.sh
# Assertion: the exact ip/nft commands are issued with the discovered gateway
#            (border network + 1), and a missing border iface yields exit 1.
# Method:    stub `ip`/`nft` on PATH, record invocations, assert on the log.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRY="${SCRIPT_DIR}/../image/entrypoint.sh"

make_stubs() { # $1 = workdir, $2 = "ready" | "missing"
  local work="$1" mode="$2" log="$1/cmd.log"
  : > "$log"
  cat > "$work/ip" <<STUB
#!/usr/bin/env bash
echo "ip \$*" >> "$log"
if [ "$mode" = ready ]; then
  case "\$*" in
    "-4 addr show dev border") echo "    inet 192.0.2.65/26 scope global border" ;;
    "-4 route list dev border scope link") echo "192.0.2.64/26 dev border proto kernel scope link" ;;
  esac
fi
exit 0
STUB
  cat > "$work/nft" <<STUB
#!/usr/bin/env bash
echo "nft \$*" >> "$log"
cat >> "$log" 2>/dev/null || true
exit 0
STUB
  chmod +x "$work/ip" "$work/nft"
}

# --- Case 1: happy path ---
WORK1="$(mktemp -d)"; trap 'rm -rf "$WORK1"' EXIT
make_stubs "$WORK1" ready
PATH="$WORK1:$PATH" \
  BR_ADDRESS="198.51.100.50/32" BORDER_IFACE=border BACKBONE_IFACE=backbone \
  RT_TABLES="$WORK1/rt_tables" WAIT_TIMEOUT=3 \
  bash "$ENTRY"
LOG="$WORK1/cmd.log"

grep -qF 'ip addr add 198.51.100.50/32 dev dummy0' "$LOG" \
  || { echo "FAIL: dummy0 address not set"; cat "$LOG"; exit 1; }
grep -qF 'ip rule add pref 98 iif backbone lookup border_egress' "$LOG" \
  || { echo "FAIL: ingress RPDB rule missing"; cat "$LOG"; exit 1; }
grep -qF 'ip route replace table border_egress default via 192.0.2.65 dev border' "$LOG" \
  || { echo "FAIL: default route / gateway discovery wrong"; cat "$LOG"; exit 1; }
grep -qF 'ip route replace table border_egress throw 100.64.0.0/10' "$LOG" \
  || { echo "FAIL: CGNAT throw missing"; cat "$LOG"; exit 1; }
grep -qF 'oifname "border" masquerade' "$LOG" \
  || { echo "FAIL: masquerade rule missing"; cat "$LOG"; exit 1; }
grep -qE '^102 border_egress$' "$WORK1/rt_tables" \
  || { echo "FAIL: rt_tables registration missing"; cat "$WORK1/rt_tables"; exit 1; }

# --- Case 2: border never ready -> fail fast ---
WORK2="$(mktemp -d)"; trap 'rm -rf "$WORK1" "$WORK2"' EXIT
make_stubs "$WORK2" missing
set +e
PATH="$WORK2:$PATH" \
  BR_ADDRESS="198.51.100.50/32" BORDER_IFACE=border BACKBONE_IFACE=backbone \
  RT_TABLES="$WORK2/rt_tables" WAIT_TIMEOUT=1 \
  bash "$ENTRY"
rc=$?
set -e
[ "$rc" -eq 1 ] || { echo "FAIL: expected exit 1 on missing border, got $rc"; exit 1; }

echo "ok: entrypoint_test"
