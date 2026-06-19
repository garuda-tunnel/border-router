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

# --- Case 3: MSS clamp enabled via BR_FIXED_MSS + BR_MSS_CLAMP_ENABLED=true ---
# The entrypoint must install a separate table inet border_mss with a forward
# chain that clamps TCP MSS in both directions on the backbone interface.
# BR_FIXED_MSS carries the value; BR_MSS_CLAMP_ENABLED=true gates the table.
WORK3="$(mktemp -d)"; trap 'rm -rf "$WORK1" "$WORK2" "$WORK3"' EXIT
make_stubs "$WORK3" ready
PATH="$WORK3:$PATH" \
  BR_ADDRESS="198.51.100.50/32" BORDER_IFACE=border BACKBONE_IFACE=backbone \
  RT_TABLES="$WORK3/rt_tables" WAIT_TIMEOUT=3 \
  BR_FIXED_MSS=1290 BR_MSS_CLAMP_ENABLED=true \
  bash "$ENTRY"

# Collect everything nft received (the stub appends stdin to cmd.log).
LOG3="$WORK3/cmd.log"

# MSS clamp table must be a separate table inet border_mss (not border_router).
grep -qF 'table inet border_mss' "$LOG3" \
  || { echo "FAIL: separate table inet border_mss missing"; cat "$LOG3"; exit 1; }
grep -qF 'iifname "backbone" tcp flags syn tcp option maxseg size set 1290' "$LOG3" \
  || { echo "FAIL: iifname backbone MSS clamp missing"; cat "$LOG3"; exit 1; }
grep -qF 'oifname "backbone" tcp flags syn tcp option maxseg size set 1290' "$LOG3" \
  || { echo "FAIL: oifname backbone MSS clamp missing"; cat "$LOG3"; exit 1; }

# AC8 negative: the ruleset must NOT drop or reject ICMP (policy accept).
if grep -qiE 'icmp.*(drop|reject)|(drop|reject).*icmp' "$LOG3"; then
  echo "FAIL: ICMP drop/reject found in ruleset"; cat "$LOG3"; exit 1
fi

# AC8 positive: forward chain default-accepts (policy accept present).
grep -qF 'policy accept' "$LOG3" \
  || { echo "FAIL: policy accept missing from forward chain"; cat "$LOG3"; exit 1; }

# --- Case 4: BR_MSS_CLAMP_ENABLED=false disables the MSS table entirely ---
WORK4="$(mktemp -d)"; trap 'rm -rf "$WORK1" "$WORK2" "$WORK3" "$WORK4"' EXIT
make_stubs "$WORK4" ready
PATH="$WORK4:$PATH" \
  BR_ADDRESS="198.51.100.50/32" BORDER_IFACE=border BACKBONE_IFACE=backbone \
  RT_TABLES="$WORK4/rt_tables" WAIT_TIMEOUT=3 \
  BR_FIXED_MSS=1290 BR_MSS_CLAMP_ENABLED=false \
  bash "$ENTRY"
LOG4="$WORK4/cmd.log"
if grep -qF 'table inet border_mss' "$LOG4"; then
  echo "FAIL: border_mss table must be absent when BR_MSS_CLAMP_ENABLED=false"; cat "$LOG4"; exit 1
fi

echo "ok: entrypoint_test"
