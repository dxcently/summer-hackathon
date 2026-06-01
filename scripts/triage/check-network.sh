#!/usr/bin/env bash
# check-network.sh — fast network reachability sweep. Designed to
# be run REPEATEDLY throughout the round (every 5-10 min) without
# noise. Output is one screen, color-coded, no log file written.
#
# Use this when:
#   - The scoreboard just flipped red on a service and you want to
#     isolate "is the box itself off the LAN?" vs "is the service
#     broken?"
#   - You changed a firewall rule and want a fast verify
#   - You want to confirm internet egress before package install
#
# Usage:
#   bash check-network.sh
#   GW=172.21.0.150 DC=172.21.0.103 bash check-network.sh
#
# Tunables (env):
#   GW       LAN gateway (default: from `ip route`)
#   DC       Domain controller / DNS (default: from /etc/resolv.conf)
#   DOMAIN   AD domain (default: rrintel.internal)
#   QUIET=1  suppress passes, only show warns + fails

set -u
LANG=C; export LANG

# Colours, with TTY detection so piped output stays clean
if [ -t 1 ]; then
    G="$(printf '\033[32m')"; R="$(printf '\033[31m')"
    Y="$(printf '\033[33m')"; N="$(printf '\033[0m')"
else
    G=""; R=""; Y=""; N=""
fi

GW="${GW:-$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')}"
DC="${DC:-$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')}"
DOMAIN="${DOMAIN:-rrintel.internal}"
QUIET="${QUIET:-0}"

ok()   { [ "$QUIET" = "1" ] || printf '  %s[ ok ]%s  %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s[warn]%s  %s\n' "$Y" "$N" "$*"; }
fail() { printf '  %s[FAIL]%s  %s\n' "$R" "$N" "$*"; }

printf '\n  utc: %s\n  gw:  %s   dc: %s   domain: %s\n\n' \
    "$(date -u +%H:%M:%SZ)" "${GW:-?}" "${DC:-?}" "$DOMAIN"

# --- LAN reach ------------------------------------------------------
if [ -n "$GW" ]; then
    if ping -c 1 -W 1 "$GW" >/dev/null 2>&1; then
        ok "gateway $GW"
    else
        fail "gateway $GW (NIC down? routing wrong?)"
    fi
else
    warn "no default gateway in route table"
fi

if [ -n "$DC" ] && [ "$DC" != "$GW" ]; then
    if ping -c 1 -W 1 "$DC" >/dev/null 2>&1; then
        ok "DC $DC"
    else
        fail "DC $DC (AD will cascade)"
    fi
fi

# --- internet -------------------------------------------------------
for tgt in 1.1.1.1 8.8.8.8; do
    if ping -c 1 -W 1 "$tgt" >/dev/null 2>&1; then
        ok "internet ($tgt)"
        break
    fi
done

# --- DNS forward + AD SRV ------------------------------------------
if command -v dig >/dev/null 2>&1; then
    if dig +short +time=1 +tries=1 "$DOMAIN" 2>/dev/null | grep -qE '^[0-9]'; then
        ok "DNS A   $DOMAIN"
    else
        fail "DNS A   $DOMAIN (does NOT resolve)"
    fi
    if dig +short +time=1 +tries=1 _ldap._tcp."$DOMAIN" SRV 2>/dev/null | grep -q .; then
        ok "DNS SRV _ldap._tcp.$DOMAIN"
    else
        warn "DNS SRV _ldap._tcp.$DOMAIN missing"
    fi
else
    warn "dig not installed — install bind-utils/dnsutils"
fi

# --- TCP probe of critical ports on the DC --------------------------
# These are the AD-cluster ports. If they're down, every AD-backed
# scored service goes red within one or two scoring rounds.
if [ -n "$DC" ]; then
    for port in 53 88 389 445 636; do
        if (echo > "/dev/tcp/$DC/$port") >/dev/null 2>&1; then
            ok "DC :$port open"
        else
            fail "DC :$port closed/filtered"
        fi
    done
fi

# --- local listener summary ----------------------------------------
LISTEN_COUNT=$(ss -tln 2>/dev/null | awk 'NR>1' | wc -l)
printf '\n  local listeners: %d\n' "$LISTEN_COUNT"
