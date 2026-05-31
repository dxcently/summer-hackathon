#!/usr/bin/env bash
# linux-triage.sh — read-only first-run triage for Blacklist (Debian 13)
# and Concierge (Fedora 43). Captures baseline state of users, network,
# services, cron, persistence vectors, and recently modified files into
# a timestamped log.
#
# Usage (as root, on the box):
#   sudo bash linux-triage.sh
#
# Output: ~/triage-<host>-<timestamp>.log
#
# This script ONLY reads. It does not change any system state.
# Safe to run multiple times; each run produces a new log file you can
# diff against the previous one to spot deltas.

set -u
LANG=C
export LANG

OUT="${HOME}/triage-$(hostname)-$(date -u +%Y%m%d-%H%M%SZ).log"
TMP_ERR="$(mktemp)"
trap 'rm -f "$TMP_ERR"' EXIT

section() {
    printf '\n\n=== %s ===\n' "$1" >>"$OUT"
}

run() {
    local label="$1"; shift
    printf '\n--- %s ---\n$ %s\n' "$label" "$*" >>"$OUT"
    "$@" >>"$OUT" 2>"$TMP_ERR" || true
    if [ -s "$TMP_ERR" ]; then
        printf '[stderr] ' >>"$OUT"
        cat "$TMP_ERR" >>"$OUT"
    fi
}

run_sh() {
    local label="$1"; shift
    local cmd="$*"
    printf '\n--- %s ---\n$ %s\n' "$label" "$cmd" >>"$OUT"
    bash -c "$cmd" >>"$OUT" 2>"$TMP_ERR" || true
    if [ -s "$TMP_ERR" ]; then
        printf '[stderr] ' >>"$OUT"
        cat "$TMP_ERR" >>"$OUT"
    fi
}

{
    printf 'eCitadel triage report\n'
    printf 'host:      %s\n' "$(hostname)"
    printf 'utc:       %s\n' "$(date -u)"
    printf 'kernel:    %s\n' "$(uname -a)"
    printf 'distro:    %s\n' "$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
    printf 'uptime:    %s\n' "$(uptime)"
    printf 'runner:    %s (euid %s)\n' "$(id -un)" "$(id -u)"
} >"$OUT"

# ---------------------------------------------------------------------
section 'USERS'
# ---------------------------------------------------------------------
run    'system accounts (uid < 1000)'   awk -F: '($3 < 1000) {print}' /etc/passwd
run    'human accounts (uid >= 1000)'   awk -F: '($3 >= 1000) {print}' /etc/passwd
run_sh 'accounts with password hashes set' \
    "awk -F: '(\$2!~\"\\\\!\"&&\$2!~\"\\\\*\"&&\$2!=\"\"){print \$1}' /etc/shadow"
run    'sudoers (main)'                 cat /etc/sudoers
run_sh 'sudoers drop-ins'               "ls -la /etc/sudoers.d/ 2>/dev/null && cat /etc/sudoers.d/* 2>/dev/null"
run    'sudo / wheel / admin groups'    getent group sudo wheel admin
run_sh 'recently changed accounts (last 7d in /etc/passwd, shadow, group)' \
    "find /etc/passwd /etc/shadow /etc/group /etc/gshadow -mtime -7 -ls 2>/dev/null"

# ---------------------------------------------------------------------
section 'NETWORK'
# ---------------------------------------------------------------------
run 'interfaces'                        ip -br a
run 'routing table'                     ip route
run 'resolv.conf'                       cat /etc/resolv.conf
run 'listening tcp'                     ss -tlnp
run 'listening udp'                     ss -ulnp
run 'established connections'           ss -tnp state established

# ---------------------------------------------------------------------
section 'SERVICES'
# ---------------------------------------------------------------------
run 'running services'                  systemctl list-units --type=service --state=running --no-pager
run 'enabled services'                  systemctl list-unit-files --state=enabled --no-pager
run 'failed services'                   systemctl list-units --state=failed --no-pager

# ---------------------------------------------------------------------
section 'SCHEDULED JOBS'
# ---------------------------------------------------------------------
run    'root crontab'                   crontab -l
run_sh 'per-user crontabs' \
    "for u in \$(awk -F: '{print \$1}' /etc/passwd); do echo \"# user \$u\"; crontab -l -u \"\$u\" 2>/dev/null; done"
run_sh 'cron drop-ins' \
    "ls -la /etc/cron.d/ /etc/cron.daily/ /etc/cron.hourly/ /etc/cron.weekly/ /etc/cron.monthly/ 2>/dev/null"
run    'cron spool'                     ls -la /var/spool/cron/ /var/spool/cron/crontabs/
run    'systemd timers'                 systemctl list-timers --all --no-pager

# ---------------------------------------------------------------------
section 'PERSISTENCE / BACKDOOR VECTORS'
# ---------------------------------------------------------------------
run    'SUID binaries'                  find / -perm -4000 -type f -not -path '/proc/*' -ls 2>/dev/null
run    'SGID binaries'                  find / -perm -2000 -type f -not -path '/proc/*' -ls 2>/dev/null
run    'orphaned files (no user/group)' find / -nouser -o -nogroup -not -path '/proc/*' -ls 2>/dev/null
run_sh 'all SSH authorized_keys files' \
    "find /root /home -name 'authorized_keys' -exec echo '## {}' \\; -exec ls -la {} \\; -exec cat {} \\; 2>/dev/null"
run_sh 'profile.d hooks'                "ls -la /etc/profile.d/ && head -n 50 /etc/profile.d/* 2>/dev/null"
run_sh 'rc.local + init.d'              "ls -la /etc/rc.local /etc/init.d/ 2>/dev/null"
run    'systemd system unit files'      ls -la /etc/systemd/system/

# ---------------------------------------------------------------------
section 'RECENT FILE CHANGES (last 7 days)'
# ---------------------------------------------------------------------
run 'modified /etc files'               find /etc -mtime -7 -type f -ls
run 'modified /usr/local files'         find /usr/local -mtime -7 -type f -ls 2>/dev/null
run 'modified /opt files'               find /opt -mtime -7 -type f -ls 2>/dev/null
run 'modified /var/www files'           find /var/www -mtime -7 -type f -ls 2>/dev/null
run 'files in /tmp /var/tmp /dev/shm'   find /tmp /var/tmp /dev/shm -type f -ls 2>/dev/null

# ---------------------------------------------------------------------
section 'PROCESSES'
# ---------------------------------------------------------------------
run 'process tree'                      ps -eo pid,ppid,user,stat,etime,cmd --forest
run_sh 'top 20 by cpu'                  "ps -eo pid,user,pcpu,pmem,cmd --sort=-pcpu | head -n 21"
run_sh 'top 20 by memory'               "ps -eo pid,user,pcpu,pmem,cmd --sort=-pmem | head -n 21"
run 'open network sockets'              lsof -i -n -P 2>/dev/null

# ---------------------------------------------------------------------
section 'WEB ARTIFACTS (Concierge)'
# ---------------------------------------------------------------------
run_sh 'webroot listing' \
    "for d in /var/www /srv/www /usr/share/nginx /opt/wp-content; do [ -d \"\$d\" ] && echo \"## \$d\" && find \"\$d\" -maxdepth 3 -type d -ls; done 2>/dev/null"
run_sh 'webshell candidates (eval/base64/system)' \
    "grep -RElE 'eval\\(|base64_decode\\(|system\\(|exec\\(|shell_exec\\(|assert\\(' /var/www /srv/www 2>/dev/null"
run_sh 'recently modified php' \
    "find /var/www /srv/www -name '*.php' -mtime -14 -ls 2>/dev/null"
run_sh 'oversized php (potential shells)' \
    "find /var/www /srv/www -name '*.php' -size +50k -ls 2>/dev/null"

# ---------------------------------------------------------------------
section 'DATABASE LISTENERS (Blacklist)'
# ---------------------------------------------------------------------
run_sh 'db service status' \
    "systemctl list-units --type=service 2>/dev/null | grep -iE 'postgres|mysql|maria|mongo|redis|mssql'"
run_sh 'db port listeners' \
    "ss -tlnp 2>/dev/null | grep -E ':5432|:3306|:1433|:27017|:6379'"

# ---------------------------------------------------------------------
section 'DOMAIN JOIN / AD INTEGRATION'
# ---------------------------------------------------------------------
run    'sssd status'                    systemctl status sssd --no-pager
run    'realm list'                     realm list
run    'sssd conf'                      cat /etc/sssd/sssd.conf
run    'nsswitch.conf'                  cat /etc/nsswitch.conf

# ---------------------------------------------------------------------
section 'SECURITY POSTURE'
# ---------------------------------------------------------------------
run    'SELinux mode (Fedora)'          getenforce
run_sh 'AppArmor status (Debian)'       "aa-status 2>/dev/null || echo 'aa-status not installed'"
run_sh 'firewall (ufw)' \
    "command -v ufw >/dev/null && ufw status verbose || echo 'ufw not installed'"
run_sh 'firewall (firewalld)' \
    "command -v firewall-cmd >/dev/null && firewall-cmd --list-all-zones || echo 'firewalld not installed'"
run_sh 'nftables ruleset' \
    "command -v nft >/dev/null && nft list ruleset || echo 'nft not installed'"
run_sh 'iptables (legacy)' \
    "command -v iptables >/dev/null && iptables -L -n -v || echo 'iptables not installed'"
run    'sshd_config'                    cat /etc/ssh/sshd_config

# ---------------------------------------------------------------------
section 'PACKAGE / UPDATE STATE'
# ---------------------------------------------------------------------
run_sh 'installed pkg count (dpkg)' \
    "command -v dpkg >/dev/null && dpkg -l 2>/dev/null | wc -l"
run_sh 'installed pkg count (rpm)' \
    "command -v rpm >/dev/null && rpm -qa 2>/dev/null | wc -l"
run_sh 'last 30 dpkg installs' \
    "command -v dpkg >/dev/null && zgrep -h 'install ' /var/log/dpkg.log* 2>/dev/null | tail -n 30"
run_sh 'last 30 dnf transactions' \
    "command -v dnf >/dev/null && dnf history list | head -n 30"

# ---------------------------------------------------------------------
section 'LOG TAILS'
# ---------------------------------------------------------------------
run    'auth log (recent)'              journalctl -n 200 --no-pager _SYSTEMD_UNIT=ssh.service
run    'system journal errors'          journalctl -p err -b --no-pager
run_sh 'last 50 successful logins'      "last -n 50"
run_sh 'last 50 bad logins'             "lastb -n 50 2>/dev/null"

# ---------------------------------------------------------------------
section 'DONE'
# ---------------------------------------------------------------------
printf '\nReport written to: %s\n' "$OUT" >>"$OUT"

echo "Triage complete."
echo "Report: $OUT"
echo
echo "Suggested next steps:"
echo "  1. Copy the report off the box to your shared notes."
echo "  2. Diff against the next run with: diff prev.log this.log"
echo "  3. Cross-check findings against docs/02-hardening.md"
