#!/bin/sh
# border_router egress-setup.
#
# Mirrors the NAT + border_egress RPDB blocks of the former wireguard
# postup.sh, WITHOUT WireGuard. Runs once as a
# Kubernetes initContainer; the kernel state it installs (dummy0, RPDB table,
# nft table) persists in the shared pod netns for the pod lifetime, so the
# long-running frr-sidecar container sees it.
#
# Single config value: BR_ADDRESS is "<ospf-router-id>/32". The same router-id
# lives on dummy0 (advertised via OSPF by the sidecar) and is the gw= next-hop
# ipt_server targets.
set -eu

BR_ADDRESS="${BR_ADDRESS:?BR_ADDRESS (<router-id>/32) is required}"
BORDER_IFACE="${BORDER_IFACE:-border}"
BACKBONE_IFACE="${BACKBONE_IFACE:-backbone}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30}"
RT_TABLES="${RT_TABLES:-/etc/iproute2/rt_tables}"
# Fixed MSS for transit TCP SYNs on backbone (both directions). 0 disables.
# border-router has only 1500-MTU interfaces; clamp-to-pmtu is a no-op here.
BR_MSS="${BR_MSS:-1240}"
TABLE_NAME="border_router"
MSS_TABLE_NAME="border_mss"

# --- 1: wait for border iface readiness (fail fast on timeout) ---
# Multus secondary attach is not strictly ordered against initContainer start.
i=0
while ! ip -4 addr show dev "$BORDER_IFACE" 2>/dev/null | grep -q 'inet '; do
    i=$((i + 1))
    if [ "$i" -ge "$WAIT_TIMEOUT" ]; then
        echo "[egress-setup] FATAL: $BORDER_IFACE not ready after ${WAIT_TIMEOUT}s" >&2
        exit 1
    fi
    sleep 1
done
echo "[egress-setup] $BORDER_IFACE ready"

# --- 2: dummy0 ingress nexthop (router-id /32) ---
ip link add dummy0 type dummy 2>/dev/null || true
ip addr add "$BR_ADDRESS" dev dummy0 2>/dev/null || true
ip link set dummy0 up
echo "[egress-setup] dummy0 = $BR_ADDRESS"

# --- 3: discover border gateway (network + 1) ---
# Byte-for-byte mirror of postup.sh:108-115.
BORDER_CIDR=$(ip -4 route list dev "$BORDER_IFACE" scope link | awk 'NR == 1 { print $1 }')
BORDER_NET=${BORDER_CIDR%/*}
IFS=. read -r A B C D <<EOF
${BORDER_NET}
EOF
INT=$(( (A << 24) + (B << 16) + (C << 8) + D + 1 ))
BORDER_GW="$(( (INT >> 24) & 255 )).$(( (INT >> 16) & 255 )).$(( (INT >> 8) & 255 )).$(( INT & 255 ))"
echo "[egress-setup] border gateway = $BORDER_GW"

# --- 4: register the RPDB table by name (literal lookup needs the name) ---
RT_DIR=$(dirname "$RT_TABLES")
mkdir -p "$RT_DIR"
touch "$RT_TABLES"
grep -q '^102 border_egress$' "$RT_TABLES" \
    || echo '102 border_egress' >> "$RT_TABLES"

# --- 5: ingress RPDB rule: backbone-ingress transit -> border_egress ---
ip rule add pref 98 iif "$BACKBONE_IFACE" lookup border_egress 2>/dev/null || true

# --- 6: border_egress routes (idempotent) ---
ip route replace table border_egress throw 10.0.0.0/8
ip route replace table border_egress throw 172.16.0.0/12
ip route replace table border_egress throw 192.168.0.0/16
ip route replace table border_egress throw 100.64.0.0/10
ip route replace table border_egress default via "$BORDER_GW" dev "$BORDER_IFACE"
echo "[egress-setup] border_egress: default via $BORDER_GW dev $BORDER_IFACE"

# --- 7: nft masquerade (border only) ---
nft add table inet "$TABLE_NAME" 2>/dev/null || true
nft delete table inet "$TABLE_NAME" 2>/dev/null || true
nft -f - <<EOF
table inet ${TABLE_NAME} {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip daddr 10.0.0.0/8 return
        ip daddr 172.16.0.0/12 return
        ip daddr 192.168.0.0/16 return
        ip daddr 100.64.0.0/10 return
        oifname "${BORDER_IFACE}" masquerade
    }
}
EOF
echo "[egress-setup] masquerade installed (oifname $BORDER_IFACE)"

# --- 8: nft MSS clamp (separate table, bidirectional, backbone) ---
# Kept in a separate table inet border_mss so masquerade in border_router is
# untouched and so the MSS clamp is independently toggleable via BR_MSS=0.
# Fixed MSS because border-router only has 1500-MTU interfaces; clamp-to-pmtu
# would resolve to 1500 and be a no-op (Task 0 DQ4). Covers both directions
# (iifname = inbound-initiated; oifname = egress toward internet).
if [ "${BR_MSS}" -gt 0 ]; then
    nft add table inet "$MSS_TABLE_NAME" 2>/dev/null || true
    nft delete table inet "$MSS_TABLE_NAME" 2>/dev/null || true
    nft -f - <<EOF
table inet ${MSS_TABLE_NAME} {
    chain forward {
        type filter hook forward priority mangle; policy accept;
        iifname "${BACKBONE_IFACE}" tcp flags syn tcp option maxseg size set ${BR_MSS}
        oifname "${BACKBONE_IFACE}" tcp flags syn tcp option maxseg size set ${BR_MSS}
    }
}
EOF
    echo "[egress-setup] MSS clamp installed (${BACKBONE_IFACE} both dirs, MSS ${BR_MSS})"
fi
