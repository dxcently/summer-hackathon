#!/bin/sh
# pfsense-triage.sh — read-only first-run triage for pfSense (thebox).
#
# Usage (in pfSense console: option 8 → shell):
#   sh /root/pfsense-triage.sh
#
# Output: /root/.ecitadel/triage-thebox-<utc-timestamp>.log
#
# Read-only. Does not modify firewall rules, NAT, or any config.
# Uses /bin/sh (BusyBox-ish on pfSense) — no bash features.

LANG=C
export LANG

WORKDIR="/root/.ecitadel"
mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR" 2>/dev/null || true
TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT="${WORKDIR}/triage-thebox-${TS}.log"

section() {
    printf '\n\n=== %s ===\n' "$1" >>"$OUT"
}

run() {
    label="$1"; shift
    printf '\n--- %s ---\n$ %s\n' "$label" "$*" >>"$OUT"
    "$@" >>"$OUT" 2>&1
}

run_sh() {
    label="$1"; shift
    cmd="$*"
    printf '\n--- %s ---\n$ %s\n' "$label" "$cmd" >>"$OUT"
    /bin/sh -c "$cmd" >>"$OUT" 2>&1
}

{
    printf 'eCitadel pfSense triage report\n'
    printf 'utc:       %s\n' "$(date -u)"
    printf 'host:      %s\n' "$(hostname)"
    printf 'version:   %s\n' "$(cat /etc/version 2>/dev/null)"
    printf 'uptime:    %s\n' "$(uptime)"
    printf 'runner:    %s (euid %s)\n' "$(id -un)" "$(id -u)"
} >"$OUT"

# ---------------------------------------------------------------------
section 'INTERFACES'
# ---------------------------------------------------------------------
run    'ifconfig'                       ifconfig
run    'interface stats'                netstat -i
run_sh 'pf interface label assignments' "grep -E 'descr|if' /cf/conf/config.xml | head -n 80"

# ---------------------------------------------------------------------
section 'PF FIREWALL RULES + STATES'
# ---------------------------------------------------------------------
run    'pf rules'                       pfctl -sr
run    'pf NAT rules'                   pfctl -sn
run    'pf state table summary'         pfctl -si
run_sh 'pf states (first 100)'          "pfctl -ss | head -n 100"
run_sh 'pf state count by direction'    "pfctl -ss | awk '{print \$3}' | sort | uniq -c | sort -rn"

# ---------------------------------------------------------------------
section 'ROUTING'
# ---------------------------------------------------------------------
run    'routing table'                  netstat -rn
run    'default route'                  route get default

# ---------------------------------------------------------------------
section 'LOCAL LISTENERS'
# ---------------------------------------------------------------------
run 'tcp listeners (sockstat)'  sockstat -4l -P tcp
run 'udp listeners (sockstat)'  sockstat -4l -P udp
run 'all sockets (sockstat)'    sockstat -4

# ---------------------------------------------------------------------
section 'PACKAGES + SERVICES'
# ---------------------------------------------------------------------
run_sh 'pkg list'                       "pkg info | head -n 80"
run_sh 'service list'                   "service -l 2>/dev/null | head -n 80"
run_sh 'running daemons'                "ps -ax -o pid,user,command | head -n 80"

# ---------------------------------------------------------------------
section 'CONFIG SUMMARY'
# ---------------------------------------------------------------------
run_sh 'admin users from config.xml'    "grep -E '<name>|<scope>' /cf/conf/config.xml | head -n 40"
run_sh 'config.xml top-level structure' "grep -E '<(system|interfaces|nat|filter|gateways|dhcpd)>' /cf/conf/config.xml"
run_sh 'NAT 1:1 rules (config.xml)' \
    "awk '/<onetoone>/,/<\\/onetoone>/' /cf/conf/config.xml"
run_sh 'inbound (rdr) NAT rules (config.xml)' \
    "awk '/<rule>/,/<\\/rule>/' /cf/conf/config.xml | head -n 200"

# ---------------------------------------------------------------------
section 'RECENT LOGINS + WEBGUI ACCESS'
# ---------------------------------------------------------------------
run_sh 'last 30 webgui auth events' \
    "tail -n 200 /var/log/auth.log 2>/dev/null | grep -E 'webgui|sshd|sudo' | tail -n 30"
run_sh 'last 30 console logins'         "last -n 30 2>/dev/null"

# ---------------------------------------------------------------------
section 'RECENT FIREWALL LOG'
# ---------------------------------------------------------------------
run_sh 'last 100 filter log lines (clog)' \
    "clog -f /var/log/filter.log 2>/dev/null | tail -n 100 || tail -n 100 /var/log/filter.log 2>/dev/null"

# ---------------------------------------------------------------------
section 'SYSTEM LOG TAIL'
# ---------------------------------------------------------------------
run_sh 'last 100 system log lines' "tail -n 100 /var/log/system.log 2>/dev/null"

# ---------------------------------------------------------------------
section 'DONE'
# ---------------------------------------------------------------------
printf '\nReport written to: %s\n' "$OUT" >>"$OUT"

echo "Triage complete."
echo "Report: $OUT"
echo
echo "Suggested next steps:"
echo "  1. SCP the report off the box to your shared notes."
echo "     ls -la $WORKDIR/"
echo "  2. Diff against the next run with: diff prev.log this.log"
echo "  3. Cross-check findings against docs/02-hardening.md (pfSense section)"
