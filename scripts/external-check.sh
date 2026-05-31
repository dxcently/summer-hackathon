#!/usr/bin/env bash
# external-check.sh — probe scored services from OUTSIDE pfSense, the way
# the scoring engine does. Run this from your VPN'd operator laptop, not
# from inside the team network.
#
# Usage:
#   bash external-check.sh <team-number>
# Example:
#   bash external-check.sh 17
#
# Reads no local files. Writes one log to the current directory:
#   ./external-check-<utc-timestamp>.log
#
# Read-only. Does not modify any remote system. Probes only your own
# team's external /24 (172.27.<team>.0/24) — NEVER point this at another
# team, the scoring engine, or red team. That is a DQ-able offence.

set -u
LANG=C
export LANG

if [ $# -lt 1 ]; then
    echo "usage: $0 <team-number>" >&2
    echo "  example: $0 17" >&2
    exit 64
fi

TEAM="$1"
case "$TEAM" in
    ''|*[!0-9]*) echo "team must be a number" >&2; exit 64 ;;
esac

BASE="172.27.${TEAM}"
DC="${BASE}.103"
WEB="${BASE}.102"
DB="${BASE}.101"
DOMAIN='rrintel.internal'

TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT="./external-check-${TS}.log"

section() {
    printf '\n\n=== %s ===\n' "$1" >>"$OUT"
}

run() {
    local label="$1"; shift
    printf '\n--- %s ---\n$ %s\n' "$label" "$*" >>"$OUT"
    "$@" >>"$OUT" 2>&1 || true
}

run_sh() {
    local label="$1"; shift
    local cmd="$*"
    printf '\n--- %s ---\n$ %s\n' "$label" "$cmd" >>"$OUT"
    bash -c "$cmd" >>"$OUT" 2>&1 || true
}

{
    printf 'eCitadel external scored-service check\n'
    printf 'utc:       %s\n' "$(date -u)"
    printf 'team:      %s\n' "$TEAM"
    printf 'targets:\n'
    printf '  Cabal (DC + DNS):  %s\n' "$DC"
    printf '  Concierge (Web):   %s\n' "$WEB"
    printf '  Blacklist (DB):    %s\n' "$DB"
    printf 'from host: %s\n' "$(hostname)"
} >"$OUT"

# ---------------------------------------------------------------------
section 'REACHABILITY'
# ---------------------------------------------------------------------
run    'icmp to Cabal'         ping -c 2 -W 2 "$DC"
run    'icmp to Concierge'     ping -c 2 -W 2 "$WEB"
run    'icmp to Blacklist'     ping -c 2 -W 2 "$DB"

# ---------------------------------------------------------------------
section 'DNS (Cabal)'
# ---------------------------------------------------------------------
run    "A record for $DOMAIN"  dig +short +timeout=3 "@$DC" "$DOMAIN"
run    "SOA for $DOMAIN"       dig +short +timeout=3 "@$DC" "$DOMAIN" SOA
run    "NS for $DOMAIN"        dig +short +timeout=3 "@$DC" "$DOMAIN" NS
run    "_ldap SRV"             dig +short +timeout=3 "@$DC" "_ldap._tcp.$DOMAIN" SRV
run    "_kerberos SRV"         dig +short +timeout=3 "@$DC" "_kerberos._tcp.$DOMAIN" SRV
run    'reverse lookup of DC'  dig +short +timeout=3 "@$DC" -x "$DC"

# ---------------------------------------------------------------------
section 'SSH'
# ---------------------------------------------------------------------
run_sh 'tcp 22 on Cabal'       "(echo > /dev/tcp/$DC/22) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 22 on Concierge'   "(echo > /dev/tcp/$WEB/22) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 22 on Blacklist'   "(echo > /dev/tcp/$DB/22) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run    'ssh banner Concierge'  ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no "$WEB" exit
run    'ssh banner Blacklist'  ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no "$DB" exit

# ---------------------------------------------------------------------
section 'HTTP / HTTPS (Concierge)'
# ---------------------------------------------------------------------
run    'http  → Concierge'     curl -ks --max-time 6 -o /dev/null -w 'status=%{http_code} time=%{time_total}s size=%{size_download}\n' "http://$WEB/"
run    'https → Concierge'     curl -ks --max-time 6 -o /dev/null -w 'status=%{http_code} time=%{time_total}s size=%{size_download}\n' "https://$WEB/"
run    'https headers'         curl -ksI --max-time 6 "https://$WEB/"
run    'https title <title>'   bash -c "curl -ks --max-time 6 https://$WEB/ | tr -d '\\n' | grep -oE '<title>[^<]*</title>'"
run    'https TLS cert subject' bash -c "echo | openssl s_client -connect $WEB:443 -servername $WEB 2>/dev/null | openssl x509 -noout -subject -issuer -dates"

# ---------------------------------------------------------------------
section 'DATABASE LISTENER (Blacklist)'
# ---------------------------------------------------------------------
run_sh 'tcp 5432 (postgres)'   "(echo > /dev/tcp/$DB/5432) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 3306 (mysql)'      "(echo > /dev/tcp/$DB/3306) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 1433 (mssql)'      "(echo > /dev/tcp/$DB/1433) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"

# ---------------------------------------------------------------------
section 'AD / LDAP (Cabal)'
# ---------------------------------------------------------------------
run_sh 'tcp 389  (ldap)'       "(echo > /dev/tcp/$DC/389) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 636  (ldaps)'      "(echo > /dev/tcp/$DC/636) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 88   (kerberos)'   "(echo > /dev/tcp/$DC/88) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 3389 (rdp)'        "(echo > /dev/tcp/$DC/3389) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 445  (smb)'        "(echo > /dev/tcp/$DC/445) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"
run_sh 'tcp 53   (dns)'        "(echo > /dev/tcp/$DC/53) >/dev/null 2>&1 && echo OPEN || echo CLOSED/FILTERED"

# ---------------------------------------------------------------------
section 'SUMMARY (pass/fail at a glance)'
# ---------------------------------------------------------------------
{
    echo "service               result"
    echo "-------------------   --------------------------"

    code=$(curl -ks --max-time 6 -o /dev/null -w '%{http_code}' "https://$WEB/" 2>/dev/null)
    case "$code" in
        200|301|302|401|403) echo "Concierge HTTPS       OK ($code)" ;;
        000)                 echo "Concierge HTTPS       UNREACHABLE" ;;
        *)                   echo "Concierge HTTPS       UNEXPECTED ($code)" ;;
    esac

    bash -c "(echo > /dev/tcp/$WEB/22) >/dev/null 2>&1" && \
        echo "Concierge SSH         OK" || echo "Concierge SSH         CLOSED/FILTERED"
    bash -c "(echo > /dev/tcp/$DB/22) >/dev/null 2>&1" && \
        echo "Blacklist SSH         OK" || echo "Blacklist SSH         CLOSED/FILTERED"

    if dig +short +timeout=3 "@$DC" "$DOMAIN" | grep -qE '^[0-9]'; then
        echo "Cabal  DNS            OK"
    else
        echo "Cabal  DNS            NO ANSWER"
    fi

    bash -c "(echo > /dev/tcp/$DC/445) >/dev/null 2>&1" && \
        echo "Cabal  SMB (445)      OK" || echo "Cabal  SMB (445)      CLOSED/FILTERED"
    bash -c "(echo > /dev/tcp/$DC/389) >/dev/null 2>&1" && \
        echo "Cabal  LDAP (389)     OK" || echo "Cabal  LDAP (389)     CLOSED/FILTERED"
} >>"$OUT"

# ---------------------------------------------------------------------
section 'DONE'
# ---------------------------------------------------------------------
printf '\nReport: %s\n' "$OUT" >>"$OUT"

echo "External check complete."
echo "Report: $OUT"
echo
echo "Reminders:"
echo "  - This probes ONLY 172.27.${TEAM}.* — never change the script to scan another team."
echo "  - Web check shows HTTP 200, but the scoring engine actually LOGS IN."
echo "    A 200 here is necessary but not sufficient; cross-check by hand."
echo "  - If something here is OPEN but the scoreboard is RED, the issue is"
echo "    likely AD-auth-dependent — check Cabal first."
