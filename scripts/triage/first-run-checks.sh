#!/usr/bin/env bash
# first-run-checks.sh — fast health + connectivity sanity sweep.
# Run this RIGHT AFTER bootstrap, BEFORE the full triage. Tells you
# in under 60 seconds whether the box is in a sane starting state:
#   - Network reach (gateway, DNS, AD bind, internet)
#   - Time sync (Kerberos breaks if clock skew > 5 min)
#   - Disk + memory headroom
#   - Available security updates
#   - TLS certificate health for HTTPS scored services
#   - Hostname / IP match what we expect
#
# Read-only. Does not change system state. Safe to run repeatedly.
#
# Usage:
#   bash first-run-checks.sh
#   GW=172.21.0.150 DC=172.21.0.103 DOMAIN=rrintel.internal bash first-run-checks.sh
#
# Tunables (env):
#   GW       LAN gateway IP (default: from `ip route`)
#   DC       Domain Controller / DNS server (default: from /etc/resolv.conf)
#   DOMAIN   AD domain to test resolve (default: rrintel.internal)

set -u
LANG=C; export LANG

WORKDIR="${HOME}/.rrintel"
mkdir -p "$WORKDIR" 2>/dev/null || true
chmod 700 "$WORKDIR" 2>/dev/null || true

TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT="${WORKDIR}/firstrun-$(hostname)-${TS}.log"

GW="${GW:-$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')}"
DC="${DC:-$(grep -m1 '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')}"
DOMAIN="${DOMAIN:-rrintel.internal}"

# --- helpers --------------------------------------------------------
PASS=0; FAIL=0; WARN=0

section() { printf '\n=== %s ===\n' "$1" | tee -a "$OUT"; }

ok()   { PASS=$((PASS+1)); printf '  [ ok ]  %s\n' "$*" | tee -a "$OUT"; }
warn() { WARN=$((WARN+1)); printf '  [warn]  %s\n' "$*" | tee -a "$OUT"; }
fail() { FAIL=$((FAIL+1)); printf '  [FAIL]  %s\n' "$*" | tee -a "$OUT"; }
info() { printf '  [info]  %s\n' "$*" | tee -a "$OUT"; }

# --- header ---------------------------------------------------------
{
    echo "Season IV first-run health check"
    echo "host:      $(hostname)"
    echo "utc:       $(date -u)"
    echo "kernel:    $(uname -r)"
    echo "distro:    $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
    echo "user:      $(id -un) (euid $(id -u))"
    echo "gw:        ${GW:-unset}"
    echo "dc:        ${DC:-unset}"
    echo "domain:    ${DOMAIN}"
} | tee "$OUT"

# --- 1. NETWORK REACH ----------------------------------------------
section 'NETWORK REACH'

if [ -n "${GW:-}" ]; then
    if ping -c 1 -W 2 "$GW" >/dev/null 2>&1; then
        ok "gateway ${GW} reachable"
    else
        fail "gateway ${GW} NOT reachable — check NIC + routes"
    fi
else
    warn "no default gateway found in routing table"
fi

if [ -n "${DC:-}" ]; then
    if ping -c 1 -W 2 "$DC" >/dev/null 2>&1; then
        ok "DC ${DC} reachable"
    else
        fail "DC ${DC} NOT reachable — AD-dependent services will fail"
    fi
fi

# Internet (for updates / package install)
if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    ok "internet egress (1.1.1.1) reachable"
else
    warn "no internet — package updates won't work; pfSense may be blocking"
fi

# --- 2. DNS ---------------------------------------------------------
section 'DNS RESOLUTION'

if command -v dig >/dev/null 2>&1; then
    if dig +short +time=2 +tries=1 "$DOMAIN" 2>/dev/null | grep -qE '^[0-9]'; then
        ok "DNS resolves ${DOMAIN}"
    else
        fail "DNS does NOT resolve ${DOMAIN} — check resolv.conf / DC"
    fi

    if dig +short +time=2 +tries=1 _ldap._tcp."$DOMAIN" SRV 2>/dev/null | grep -q .; then
        ok "AD _ldap._tcp SRV record present"
    else
        warn "no _ldap._tcp SRV — AD discovery may fail"
    fi
else
    warn "dig not installed — install bind-utils/dnsutils then re-run"
fi

# --- 3. TIME SYNC (Kerberos-critical) -------------------------------
section 'TIME SYNC'

if command -v timedatectl >/dev/null 2>&1; then
    SYNCED=$(timedatectl show --property=NTPSynchronized --value 2>/dev/null)
    if [ "$SYNCED" = "yes" ]; then
        ok "system time NTP-synced (Kerberos safe)"
    else
        fail "time NOT NTP-synced — fix before AD work (Kerberos breaks > 5 min skew)"
        info "  try: sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd"
    fi
fi

# Compare to a public time source if internet works
if command -v curl >/dev/null 2>&1; then
    LOCAL=$(date -u +%s)
    REMOTE=$(curl -sI --max-time 3 https://www.google.com 2>/dev/null \
             | grep -i '^date:' | sed 's/^[Dd]ate: //' | tr -d '\r')
    if [ -n "$REMOTE" ]; then
        REMOTE_TS=$(date -u -d "$REMOTE" +%s 2>/dev/null || echo 0)
        if [ "$REMOTE_TS" -gt 0 ]; then
            SKEW=$((LOCAL - REMOTE_TS))
            SKEW_ABS=${SKEW#-}
            if [ "$SKEW_ABS" -lt 30 ]; then
                ok "clock skew vs internet: ${SKEW}s (within 30s)"
            elif [ "$SKEW_ABS" -lt 300 ]; then
                warn "clock skew vs internet: ${SKEW}s (>30s, fix before AD)"
            else
                fail "clock skew vs internet: ${SKEW}s (>5 min — Kerberos WILL fail)"
            fi
        fi
    fi
fi

# --- 4. RESOURCE BASELINE -------------------------------------------
section 'RESOURCE BASELINE'

DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
if [ -n "$DISK_PCT" ]; then
    if [ "$DISK_PCT" -lt 80 ]; then
        ok "root disk ${DISK_PCT}% used"
    elif [ "$DISK_PCT" -lt 90 ]; then
        warn "root disk ${DISK_PCT}% used — getting tight"
    else
        fail "root disk ${DISK_PCT}% used — clear space soon"
    fi
fi

MEM_AVAIL=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
MEM_TOTAL=$(awk '/MemTotal/     {printf "%.0f", $2/1024}' /proc/meminfo)
if [ -n "$MEM_AVAIL" ] && [ -n "$MEM_TOTAL" ]; then
    info "memory: ${MEM_AVAIL} MB free of ${MEM_TOTAL} MB"
fi

LOAD=$(awk '{print $1}' /proc/loadavg)
NPROC=$(nproc 2>/dev/null || echo 1)
info "load: ${LOAD} (across ${NPROC} cpu)"

# --- 5. AVAILABLE SECURITY UPDATES ---------------------------------
section 'AVAILABLE SECURITY UPDATES'

if command -v apt-get >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
        SEC_COUNT=$(apt list --upgradable 2>/dev/null | grep -ci 'security' || true)
        if [ "$SEC_COUNT" -gt 0 ]; then
            warn "${SEC_COUNT} security updates available (run: sudo apt upgrade)"
        else
            ok "no security updates pending"
        fi
    fi
elif command -v dnf >/dev/null 2>&1; then
    SEC_COUNT=$(dnf updateinfo list security 2>/dev/null | grep -c '^[A-Z]' || true)
    if [ "$SEC_COUNT" -gt 0 ]; then
        warn "${SEC_COUNT} security updates available (run: sudo dnf upgrade --security)"
    else
        ok "no security updates pending"
    fi
fi

# --- 6. TLS CERTIFICATES (for HTTPS scored services) ----------------
section 'TLS CERTIFICATES'

for cert in /etc/pki/tls/certs/*.crt \
            /etc/ssl/certs/ssl-cert-snakeoil.pem \
            /etc/letsencrypt/live/*/cert.pem \
            /etc/nginx/ssl/*.crt /etc/nginx/ssl/*.pem \
            /etc/apache2/ssl/*.crt /etc/httpd/conf/ssl.crt/*.crt; do
    [ -f "$cert" ] || continue
    if command -v openssl >/dev/null 2>&1; then
        NOT_AFTER=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
        if [ -n "$NOT_AFTER" ]; then
            EXP_TS=$(date -u -d "$NOT_AFTER" +%s 2>/dev/null || echo 0)
            NOW_TS=$(date -u +%s)
            DAYS=$(( (EXP_TS - NOW_TS) / 86400 ))
            if [ "$EXP_TS" -eq 0 ]; then
                warn "$cert — could not parse expiry"
            elif [ "$DAYS" -lt 0 ]; then
                fail "$cert EXPIRED ($DAYS days)"
            elif [ "$DAYS" -lt 30 ]; then
                warn "$cert expires in ${DAYS} days"
            else
                ok "$cert valid (${DAYS} days)"
            fi
        fi
    fi
done

# --- 7. HOSTNAME / IP SANITY ----------------------------------------
section 'IDENTITY'

HOST=$(hostname)
FQDN=$(hostname --fqdn 2>/dev/null || hostname -f 2>/dev/null || hostname)
info "hostname: ${HOST}"
info "fqdn:     ${FQDN}"

PRIMARY_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
[ -z "$PRIMARY_IP" ] && PRIMARY_IP=$(hostname -I | awk '{print $1}')
info "primary ip: ${PRIMARY_IP:-unknown}"

if command -v dig >/dev/null 2>&1 && [ -n "$PRIMARY_IP" ] && [ -n "${DC:-}" ]; then
    RDNS=$(dig +short +time=2 +tries=1 "@${DC}" -x "$PRIMARY_IP" 2>/dev/null | head -1)
    if [ -n "$RDNS" ]; then
        ok "reverse DNS: ${PRIMARY_IP} → ${RDNS}"
    else
        warn "no reverse DNS record for ${PRIMARY_IP} on DC"
    fi
fi

# --- SUMMARY --------------------------------------------------------
section 'SUMMARY'

TOTAL=$((PASS + WARN + FAIL))
{
    printf '\n  passed:  %d\n' "$PASS"
    printf   '  warn:    %d\n' "$WARN"
    printf   '  failed:  %d\n' "$FAIL"
    printf   '  total:   %d\n\n' "$TOTAL"
} | tee -a "$OUT"

if [ "$FAIL" -gt 0 ]; then
    echo "  [!]  $FAIL hard failures — address before running full triage" | tee -a "$OUT"
elif [ "$WARN" -gt 0 ]; then
    echo "  [.]  ${WARN} warnings — review, then proceed" | tee -a "$OUT"
else
    echo "  [+]  box is healthy — proceed with linux-triage.sh" | tee -a "$OUT"
fi

echo
echo "Full log: $OUT"
