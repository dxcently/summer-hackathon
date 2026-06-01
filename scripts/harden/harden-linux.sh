#!/usr/bin/env bash
# harden-linux.sh — apply safe hardenings to Blacklist (Debian 13) or
# Concierge (Fedora 43). Inspired by the cyberpatriot-script ecosystem
# but with the round-breaking moves removed.
#
# WHAT IT DOES (all idempotent, all verified after write, all logged):
#   1. /etc/login.defs           — PASS_MIN_DAYS, PASS_MAX_DAYS,
#                                  PASS_MIN_LEN, PASS_WARN_AGE, UMASK
#   2. /etc/security/pwquality.conf — minlen, complexity credits,
#                                  enforce_for_root, dictcheck
#   3. /etc/ssh/sshd_config      — PermitRootLogin no,
#                                  PermitEmptyPasswords no,
#                                  MaxAuthTries 4, LoginGraceTime 30,
#                                  ClientAlive*, X11Forwarding no,
#                                  UsePAM yes
#   4. /etc/sysctl.d/99-rrintel-harden.conf — kernel + network safety
#                                  (rp_filter, accept_redirects=0,
#                                  syncookies=1, kptr_restrict=2,
#                                  yama.ptrace_scope=1, etc.)
#   5. /etc/cron.allow + /etc/at.allow — restrict to root only
#   6. /etc/shadow + /etc/gshadow perms — verify safe (640 root:shadow
#                                  or 000), report if not
#
# WHAT IT WILL NOT DO (and why):
#   - Touch ufw/firewalld/nftables. Local-firewall edits without
#     knowing the scored-service list can drop SSH/HTTP/DB/AD ports.
#   - Set PasswordAuthentication=no in sshd_config. The scoring engine
#     likely auths with a password; flipping to key-only mid-round
#     locks it out.
#   - Reset, lock, or expire any user password. Mass account changes
#     break scoring engines that have cached creds.
#   - Disable services. We don't know which ones are scored on this
#     box; the operator does.
#   - Remove SUID bits. Breaking sudo/su/passwd/mount makes the box
#     unrepairable mid-round.
#   - Touch existing /etc/sysctl.conf — we drop our settings in a NEW
#     file at /etc/sysctl.d/99-rrintel-harden.conf so we don't fight
#     vendor or operator overrides.
#
# Every edited file is backed up to:
#   ~/.rrintel/backups/<utc-ts>/<original-absolute-path>
#
# Usage (as root):
#   sudo bash harden-linux.sh --dry-run
#   sudo bash harden-linux.sh
#   sudo MIN_LEN=16 MAX_AGE_DAYS=45 bash harden-linux.sh
#   sudo DO_SYSCTL=0 bash harden-linux.sh        # skip a section
#
# Tunables (env):
#   MIN_LEN         min password length         (default 14)
#   MAX_AGE_DAYS    PASS_MAX_DAYS               (default 60)
#   MIN_AGE_DAYS    PASS_MIN_DAYS               (default 1)
#   WARN_AGE        PASS_WARN_AGE               (default 7)
#   DO_LOGIN_DEFS   include login.defs section  (default 1)
#   DO_PWQUALITY    include pwquality section   (default 1)
#   DO_SSHD         include sshd_config section (default 1)
#   DO_SYSCTL       include sysctl section      (default 1)
#   DO_CRON         include cron.allow section  (default 1)
#   DO_PERMS        include /etc/shadow perms   (default 1)

set -u
LANG=C; export LANG

# --- args -----------------------------------------------------------
DRY_RUN=0
case "${1:-}" in
    --dry-run|-n) DRY_RUN=1 ;;
    -h|--help)
        sed -n '2,60p' "$0"
        exit 0 ;;
esac

# --- tunables -------------------------------------------------------
MIN_LEN="${MIN_LEN:-14}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-60}"
MIN_AGE_DAYS="${MIN_AGE_DAYS:-1}"
WARN_AGE="${WARN_AGE:-7}"

DO_LOGIN_DEFS="${DO_LOGIN_DEFS:-1}"
DO_PWQUALITY="${DO_PWQUALITY:-1}"
DO_SSHD="${DO_SSHD:-1}"
DO_SYSCTL="${DO_SYSCTL:-1}"
DO_CRON="${DO_CRON:-1}"
DO_PERMS="${DO_PERMS:-1}"

# --- workdir + log --------------------------------------------------
WORKDIR="${HOME}/.rrintel"
mkdir -p "$WORKDIR" 2>/dev/null || true
chmod 700 "$WORKDIR" 2>/dev/null || true

TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT="${WORKDIR}/harden-linux-$(hostname)-${TS}.log"
BACKUPS="${WORKDIR}/backups/${TS}"

APPLIED=0; SKIPPED=0; FAILED=0

if [ -t 1 ]; then
    G="$(printf '\033[32m')"; R="$(printf '\033[31m')"
    Y="$(printf '\033[33m')"; C="$(printf '\033[36m')"; N="$(printf '\033[0m')"
else
    G=""; R=""; Y=""; C=""; N=""
fi

section() { printf '\n=== %s ===\n' "$1" | tee -a "$OUT"; }
mark_ok()   { APPLIED=$((APPLIED+1)); printf '  %s[ ok ]%s  %s\n' "$G" "$N" "$*" | tee -a "$OUT"; }
mark_skip() { SKIPPED=$((SKIPPED+1)); printf '  [skip]  %s\n' "$*" | tee -a "$OUT"; }
mark_dry()  {                          printf '  %s[DRY ]%s  %s\n' "$C" "$N" "$*" | tee -a "$OUT"; }
mark_fail() { FAILED=$((FAILED+1));  printf '  %s[FAIL]%s  %s\n' "$R" "$N" "$*" | tee -a "$OUT"; }
info()      { printf '  [info]  %s\n' "$*" | tee -a "$OUT"; }

# --- header ---------------------------------------------------------
{
    echo "Season IV Linux hardening"
    echo "host:    $(hostname)"
    echo "utc:     $(date -u)"
    echo "distro:  $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
    echo "user:    $(id -un) (euid $(id -u))"
    echo "dryrun:  $DRY_RUN"
    echo "policy:  minlen=$MIN_LEN max_age=${MAX_AGE_DAYS}d min_age=${MIN_AGE_DAYS}d warn_age=${WARN_AGE}d"
    echo "log:     $OUT"
    echo "backups: $BACKUPS/"
} | tee "$OUT"

if [ "$(id -u)" -ne 0 ]; then
    mark_fail "must run as root (try: sudo bash $0)"
    exit 1
fi

# --- helpers --------------------------------------------------------
backup_file() {
    local f=$1
    [ -f "$f" ] || return 0
    [ "$DRY_RUN" = "1" ] && return 0
    local dst="${BACKUPS}${f}"
    mkdir -p "$(dirname "$dst")"
    cp -p -- "$f" "$dst"
}

# set_kv_space <file> <key> <value> — files like /etc/login.defs
set_kv_space() {
    local file=$1 key=$2 val=$3
    local label="${file}: ${key}"

    local cur=""
    if [ -f "$file" ]; then
        cur=$(awk -v k="$key" '$1==k {print $2; exit}' "$file")
    fi

    if [ "$cur" = "$val" ]; then
        mark_skip "$label already = $val"
        return
    fi

    if [ "$DRY_RUN" = "1" ]; then
        mark_dry "$label : ${cur:-<missing>} -> $val"
        return
    fi

    backup_file "$file"
    if [ -n "$cur" ]; then
        if ! sed -i -E "s|^([[:space:]]*${key}[[:space:]]+).*|\1${val}|" "$file"; then
            mark_fail "$label : sed edit failed"
            return
        fi
    else
        printf '\n%s\t%s\n' "$key" "$val" >> "$file"
    fi

    local post
    post=$(awk -v k="$key" '$1==k {print $2; exit}' "$file")
    if [ "$post" = "$val" ]; then
        mark_ok "$label : ${cur:-<missing>} -> $val"
    else
        mark_fail "$label : write succeeded but verify reads '$post'"
    fi
}

# set_kv_equals <file> <key> <value> — files like pwquality.conf
set_kv_equals() {
    local file=$1 key=$2 val=$3
    local label="${file}: ${key}"

    local cur=""
    if [ -f "$file" ]; then
        cur=$(awk -F'=' -v k="$key" '$1 ~ ("^[[:space:]]*" k "[[:space:]]*$") {gsub(/[ \t]/,"",$2); print $2; exit}' "$file")
    fi

    if [ "$cur" = "$val" ]; then
        mark_skip "$label already = $val"
        return
    fi

    if [ "$DRY_RUN" = "1" ]; then
        mark_dry "$label : ${cur:-<missing>} -> $val"
        return
    fi

    backup_file "$file"
    if [ ! -f "$file" ]; then
        printf '%s = %s\n' "$key" "$val" > "$file"
    elif [ -n "$cur" ]; then
        if ! sed -i -E "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*).*|\1${val}|" "$file"; then
            mark_fail "$label : sed edit failed"
            return
        fi
    else
        printf '\n%s = %s\n' "$key" "$val" >> "$file"
    fi

    local post
    post=$(awk -F'=' -v k="$key" '$1 ~ ("^[[:space:]]*" k "[[:space:]]*$") {gsub(/[ \t]/,"",$2); print $2; exit}' "$file")
    if [ "$post" = "$val" ]; then
        mark_ok "$label : ${cur:-<missing>} -> $val"
    else
        mark_fail "$label : write succeeded but verify reads '$post'"
    fi
}

# set_sshd <keyword> <value> — sshd_config: "Keyword Value", case-insensitive
set_sshd() {
    local key=$1 val=$2
    local file=/etc/ssh/sshd_config
    local label="sshd_config: ${key}"

    [ -f "$file" ] || { mark_fail "$label : $file missing"; return; }

    local cur
    cur=$(grep -iE "^[[:space:]]*${key}[[:space:]]+" "$file" | tail -1 | awk '{print $2}')

    if [ "$(printf '%s' "${cur:-}" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$val" | tr 'A-Z' 'a-z')" ]; then
        mark_skip "$label already = $val"
        return
    fi

    if [ "$DRY_RUN" = "1" ]; then
        mark_dry "$label : ${cur:-<missing>} -> $val"
        return
    fi

    backup_file "$file"
    if [ -n "${cur:-}" ]; then
        if ! sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+.*$|${key} ${val}|I" "$file"; then
            mark_fail "$label : sed edit failed"
            return
        fi
    else
        printf '\n%s %s\n' "$key" "$val" >> "$file"
    fi

    local post
    post=$(grep -iE "^[[:space:]]*${key}[[:space:]]+" "$file" | tail -1 | awk '{print $2}')
    if [ "$(printf '%s' "${post:-}" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$val" | tr 'A-Z' 'a-z')" ]; then
        mark_ok "$label : ${cur:-<missing>} -> $val"
    else
        mark_fail "$label : write succeeded but verify reads '${post:-<missing>}'"
    fi
}

# --- 1. /etc/login.defs --------------------------------------------
if [ "$DO_LOGIN_DEFS" = "1" ]; then
    section 'login.defs'

    set_kv_space /etc/login.defs PASS_MIN_DAYS "$MIN_AGE_DAYS"
    set_kv_space /etc/login.defs PASS_MAX_DAYS "$MAX_AGE_DAYS"
    set_kv_space /etc/login.defs PASS_MIN_LEN  "$MIN_LEN"
    set_kv_space /etc/login.defs PASS_WARN_AGE "$WARN_AGE"
    set_kv_space /etc/login.defs UMASK         "027"
fi

# --- 2. /etc/security/pwquality.conf -------------------------------
if [ "$DO_PWQUALITY" = "1" ]; then
    section 'pwquality.conf'

    if [ ! -d /etc/security ]; then
        info '/etc/security missing — skipping pwquality (libpwquality not installed?)'
    else
        set_kv_equals /etc/security/pwquality.conf minlen           "$MIN_LEN"
        set_kv_equals /etc/security/pwquality.conf dcredit          "-1"
        set_kv_equals /etc/security/pwquality.conf ucredit          "-1"
        set_kv_equals /etc/security/pwquality.conf lcredit          "-1"
        set_kv_equals /etc/security/pwquality.conf ocredit          "-1"
        set_kv_equals /etc/security/pwquality.conf enforce_for_root "1"
        set_kv_equals /etc/security/pwquality.conf dictcheck        "1"
        set_kv_equals /etc/security/pwquality.conf retry            "3"
    fi
fi

# --- 3. /etc/ssh/sshd_config ---------------------------------------
if [ "$DO_SSHD" = "1" ]; then
    section 'sshd_config'

    # DO NOT touch PasswordAuthentication — scoring engine may use passwords.
    # DO NOT touch PubkeyAuthentication.
    set_sshd PermitRootLogin       no
    set_sshd PermitEmptyPasswords  no
    set_sshd MaxAuthTries          4
    set_sshd LoginGraceTime        30
    set_sshd ClientAliveInterval   300
    set_sshd ClientAliveCountMax   2
    set_sshd X11Forwarding         no
    set_sshd UsePAM                yes
    set_sshd IgnoreRhosts          yes
    set_sshd HostbasedAuthentication no

    if [ "$DRY_RUN" = "0" ] && command -v sshd >/dev/null 2>&1; then
        if sshd -t 2>/tmp/sshd-t.$$; then
            mark_ok "sshd -t (config validates)"
            info "to apply: systemctl reload sshd"
        else
            mark_fail "sshd -t FAILED — do NOT reload. Output:"
            sed 's/^/        /' /tmp/sshd-t.$$ | tee -a "$OUT"
        fi
        rm -f /tmp/sshd-t.$$
    fi
fi

# --- 4. /etc/sysctl.d/99-rrintel-harden.conf ----------------------
if [ "$DO_SYSCTL" = "1" ]; then
    section 'sysctl'

    SCTL=/etc/sysctl.d/99-rrintel-harden.conf

    DESIRED=$(cat <<'EOF'
# Season IV hardening — written by harden-linux.sh
# Network anti-spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Kernel pointer/info disclosure
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# Core dumps off (suid binaries won't dump credentials)
fs.suid_dumpable = 0

# Full ASLR
kernel.randomize_va_space = 2
EOF
)

    if [ -f "$SCTL" ] && [ "$(cat "$SCTL")" = "$DESIRED" ]; then
        mark_skip "$SCTL already at target"
    elif [ "$DRY_RUN" = "1" ]; then
        mark_dry "would write $SCTL ($(printf '%s\n' "$DESIRED" | wc -l) lines) and run sysctl --system"
    else
        backup_file "$SCTL"
        if printf '%s\n' "$DESIRED" > "$SCTL"; then
            chmod 644 "$SCTL"
            if sysctl --system >/dev/null 2>"${WORKDIR}/sysctl-apply.err"; then
                mark_ok "$SCTL written + applied via sysctl --system"
            else
                mark_fail "wrote $SCTL but sysctl --system errored (see ${WORKDIR}/sysctl-apply.err)"
            fi
        else
            mark_fail "could not write $SCTL"
        fi
    fi
fi

# --- 5. cron.allow / at.allow --------------------------------------
if [ "$DO_CRON" = "1" ]; then
    section 'cron.allow / at.allow'

    for f in /etc/cron.allow /etc/at.allow; do
        cur=""
        [ -f "$f" ] && cur=$(tr '\n' ' ' < "$f" | sed 's/[[:space:]]*$//')

        if [ "$cur" = "root" ]; then
            mark_skip "$f already = root only"
            continue
        fi

        if [ "$DRY_RUN" = "1" ]; then
            mark_dry "$f : '${cur:-<missing>}' -> 'root'"
            continue
        fi

        backup_file "$f"
        if echo "root" > "$f" && chmod 600 "$f"; then
            post=$(tr '\n' ' ' < "$f" | sed 's/[[:space:]]*$//')
            if [ "$post" = "root" ]; then
                mark_ok "$f : '${cur:-<missing>}' -> 'root' (perm 600)"
            else
                mark_fail "$f : verify mismatch (reads '$post')"
            fi
        else
            mark_fail "$f : write failed"
        fi
    done
fi

# --- 6. /etc/shadow + /etc/gshadow permissions ---------------------
if [ "$DO_PERMS" = "1" ]; then
    section 'shadow file permissions'

    for spec in \
        "/etc/passwd  644 root:root" \
        "/etc/group   644 root:root" \
        "/etc/shadow  640 root:shadow" \
        "/etc/gshadow 640 root:shadow"
    do
        # shellcheck disable=SC2086
        set -- $spec
        f=$1; want_mode=$2; want_own=$3

        [ -e "$f" ] || { info "$f missing — skipping"; continue; }

        cur_mode=$(stat -c '%a' "$f")
        cur_own=$(stat -c '%U:%G' "$f")

        # /etc/shadow on Debian: 640 root:shadow. On some Fedora setups: 000 root:root.
        if [ "$f" = "/etc/shadow" ] || [ "$f" = "/etc/gshadow" ]; then
            if [ "$cur_mode" = "000" ] || \
               { [ "$cur_mode" = "640" ] && [ "$cur_own" = "root:shadow" ]; } || \
               { [ "$cur_mode" = "640" ] && [ "$cur_own" = "root:root" ]; }; then
                mark_skip "$f perms safe ($cur_mode $cur_own)"
                continue
            fi
        else
            if [ "$cur_mode" = "$want_mode" ] && [ "$cur_own" = "$want_own" ]; then
                mark_skip "$f perms safe ($cur_mode $cur_own)"
                continue
            fi
        fi

        if [ "$DRY_RUN" = "1" ]; then
            mark_dry "$f : $cur_mode $cur_own -> $want_mode $want_own"
            continue
        fi

        backup_file "$f"
        chown "$want_own" "$f" 2>/dev/null
        chmod "$want_mode" "$f" 2>/dev/null
        post_mode=$(stat -c '%a' "$f")
        post_own=$(stat -c '%U:%G' "$f")
        if [ "$post_mode" = "$want_mode" ] && [ "$post_own" = "$want_own" ]; then
            mark_ok "$f : $cur_mode $cur_own -> $post_mode $post_own"
        else
            mark_fail "$f : verify shows $post_mode $post_own (wanted $want_mode $want_own)"
        fi
    done
fi

# --- summary -------------------------------------------------------
section 'SUMMARY'

TOTAL=$((APPLIED + SKIPPED + FAILED))
{
    printf '\n  applied:  %d\n' "$APPLIED"
    printf   '  skipped:  %d  (already at target)\n' "$SKIPPED"
    printf   '  failed:   %d\n' "$FAILED"
    printf   '  total:    %d\n\n' "$TOTAL"
} | tee -a "$OUT"

if [ "$FAILED" -gt 0 ]; then
    echo "  [!]  $FAILED hard failures — see $OUT" | tee -a "$OUT"
    EXIT=2
elif [ "$DRY_RUN" = "1" ]; then
    echo "  [.]  dry run — re-run without --dry-run to apply" | tee -a "$OUT"
    EXIT=0
else
    echo "  [+]  hardening applied. Verify with check-policy-linux.sh" | tee -a "$OUT"
    EXIT=0
fi

if [ "$DO_SSHD" = "1" ] && [ "$DRY_RUN" = "0" ] && [ "$FAILED" -eq 0 ]; then
    echo
    echo "  Reload sshd to pick up changes:  sudo systemctl reload sshd"
fi

echo
echo "Log:     $OUT"
echo "Backups: $BACKUPS/"
exit $EXIT
