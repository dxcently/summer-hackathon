#!/usr/bin/env bash
# check-policy-linux.sh — read-only audit of password policy + account
# state on Blacklist / Concierge. Categorical pass/warn/fail per check.
#
# What it flags:
#   - PASS_MIN_DAYS = 0 (allows immediate re-change after forced reset)
#   - PASS_MIN_LEN  < threshold (default: hard fail < 6, warn < 14)
#   - PASS_MAX_DAYS > threshold (default: warn > 90)
#   - pwquality: minlen, complexity credits, enforce_for_root
#   - PAM stack: pam_pwquality + password history (remember=) wired in
#   - per-user `chage -l`: never-expiring passwords, min=0
#   - multiple UID 0 accounts
#   - empty password hashes in /etc/shadow
#   - unlocked system accounts (UID < 1000 without ! or * in shadow)
#   - sshd_config: PermitRootLogin, PasswordAuthentication,
#     PermitEmptyPasswords, MaxAuthTries
#   - sudoers NOPASSWD entries
#
# Read-only. Does not change config. Safe to run repeatedly.
#
# Usage:
#   sudo bash check-policy-linux.sh
#   HARD_MIN_LEN=8 MIN_LEN=16 MAX_AGE_DAYS=60 sudo bash check-policy-linux.sh
#
# Tunables (env):
#   HARD_MIN_LEN   FAIL if min password length < this  (default: 6)
#   MIN_LEN        WARN if min password length < this  (default: 14)
#   MAX_AGE_DAYS   WARN if PASS_MAX_DAYS > this        (default: 90)
#   MIN_AGE_DAYS   WARN if PASS_MIN_DAYS < this        (default: 1)

set -u
LANG=C; export LANG

WORKDIR="${HOME}/.rrintel"
mkdir -p "$WORKDIR" 2>/dev/null || true
chmod 700 "$WORKDIR" 2>/dev/null || true

TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT="${WORKDIR}/policy-$(hostname)-${TS}.log"

HARD_MIN_LEN="${HARD_MIN_LEN:-6}"
MIN_LEN="${MIN_LEN:-14}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-90}"
MIN_AGE_DAYS="${MIN_AGE_DAYS:-1}"

PASS=0; FAIL=0; WARN=0

if [ -t 1 ]; then
    G="$(printf '\033[32m')"; R="$(printf '\033[31m')"
    Y="$(printf '\033[33m')"; N="$(printf '\033[0m')"
else
    G=""; R=""; Y=""; N=""
fi

section() { printf '\n=== %s ===\n' "$1" | tee -a "$OUT"; }
ok()   { PASS=$((PASS+1)); printf '  %s[ ok ]%s  %s\n' "$G" "$N" "$*" | tee -a "$OUT"; }
warn() { WARN=$((WARN+1)); printf '  %s[warn]%s  %s\n' "$Y" "$N" "$*" | tee -a "$OUT"; }
fail() { FAIL=$((FAIL+1)); printf '  %s[FAIL]%s  %s\n' "$R" "$N" "$*" | tee -a "$OUT"; }
info() { printf '  [info]  %s\n' "$*" | tee -a "$OUT"; }

# --- header ---------------------------------------------------------
{
    echo "Season IV policy audit (linux)"
    echo "host:      $(hostname)"
    echo "utc:       $(date -u)"
    echo "distro:    $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
    echo "user:      $(id -un) (euid $(id -u))"
    echo "thresholds: hard_min_len=${HARD_MIN_LEN} warn_min_len=${MIN_LEN} max_age=${MAX_AGE_DAYS}d min_age=${MIN_AGE_DAYS}d"
} | tee "$OUT"

if [ "$(id -u)" -ne 0 ]; then
    warn "not running as root — /etc/shadow, chage -l, and sudoers checks will be skipped or partial"
fi

# --- 1. /etc/login.defs --------------------------------------------
section 'PASSWORD AGING (/etc/login.defs)'

if [ -r /etc/login.defs ]; then
    LD_MIN=$(awk  '/^PASS_MIN_DAYS/  {print $2; exit}' /etc/login.defs)
    LD_MAX=$(awk  '/^PASS_MAX_DAYS/  {print $2; exit}' /etc/login.defs)
    LD_LEN=$(awk  '/^PASS_MIN_LEN/   {print $2; exit}' /etc/login.defs)
    LD_WARN=$(awk '/^PASS_WARN_AGE/  {print $2; exit}' /etc/login.defs)

    info "PASS_MIN_DAYS=${LD_MIN:-?}  PASS_MAX_DAYS=${LD_MAX:-?}  PASS_MIN_LEN=${LD_LEN:-?}  PASS_WARN_AGE=${LD_WARN:-?}"

    if [ -n "${LD_MIN:-}" ]; then
        if [ "$LD_MIN" -lt "$MIN_AGE_DAYS" ]; then
            warn "PASS_MIN_DAYS=$LD_MIN — allows users to cycle history immediately (set >= $MIN_AGE_DAYS)"
        else
            ok "PASS_MIN_DAYS=$LD_MIN"
        fi
    else
        warn "PASS_MIN_DAYS not set in /etc/login.defs"
    fi

    if [ -n "${LD_MAX:-}" ]; then
        if [ "$LD_MAX" -gt "$MAX_AGE_DAYS" ]; then
            warn "PASS_MAX_DAYS=$LD_MAX (> ${MAX_AGE_DAYS}d)"
        elif [ "$LD_MAX" -le 0 ]; then
            warn "PASS_MAX_DAYS=$LD_MAX (passwords never expire)"
        else
            ok "PASS_MAX_DAYS=$LD_MAX"
        fi
    fi

    if [ -n "${LD_LEN:-}" ]; then
        if [ "$LD_LEN" -lt "$HARD_MIN_LEN" ]; then
            fail "PASS_MIN_LEN=$LD_LEN (< $HARD_MIN_LEN — weak)"
        elif [ "$LD_LEN" -lt "$MIN_LEN" ]; then
            warn "PASS_MIN_LEN=$LD_LEN (< $MIN_LEN — could be stronger)"
        else
            ok "PASS_MIN_LEN=$LD_LEN"
        fi
    else
        warn "PASS_MIN_LEN not set (pwquality may still enforce minlen)"
    fi
else
    warn "/etc/login.defs not readable"
fi

# --- 2. /etc/security/pwquality.conf -------------------------------
section 'PAM PASSWORD QUALITY (pwquality.conf)'

PWQ=/etc/security/pwquality.conf
if [ -r "$PWQ" ]; then
    get_pwq() { awk -F'=' -v k="$1" '$1 ~ ("^[[:space:]]*" k "[[:space:]]*$") {gsub(/[ \t]/,"",$2); print $2; exit}' "$PWQ"; }

    PWQ_MINLEN=$(get_pwq minlen)
    PWQ_DCRED=$(get_pwq  dcredit)
    PWQ_UCRED=$(get_pwq  ucredit)
    PWQ_LCRED=$(get_pwq  lcredit)
    PWQ_OCRED=$(get_pwq  ocredit)
    PWQ_EFR=$(get_pwq    enforce_for_root)
    PWQ_RETRY=$(get_pwq  retry)
    PWQ_DICT=$(get_pwq   dictcheck)

    info "minlen=${PWQ_MINLEN:-?} dcredit=${PWQ_DCRED:-?} ucredit=${PWQ_UCRED:-?} lcredit=${PWQ_LCRED:-?} ocredit=${PWQ_OCRED:-?} retry=${PWQ_RETRY:-?}"

    if [ -n "${PWQ_MINLEN:-}" ]; then
        if [ "$PWQ_MINLEN" -lt "$HARD_MIN_LEN" ]; then
            fail "pwquality minlen=$PWQ_MINLEN (< $HARD_MIN_LEN)"
        elif [ "$PWQ_MINLEN" -lt "$MIN_LEN" ]; then
            warn "pwquality minlen=$PWQ_MINLEN (< $MIN_LEN)"
        else
            ok "pwquality minlen=$PWQ_MINLEN"
        fi
    else
        warn "pwquality minlen not configured"
    fi

    if [ "${PWQ_DCRED:-0}" = "0" ] && [ "${PWQ_UCRED:-0}" = "0" ] \
       && [ "${PWQ_LCRED:-0}" = "0" ] && [ "${PWQ_OCRED:-0}" = "0" ]; then
        warn "no complexity required (all *credit values 0)"
    else
        ok "complexity rules present"
    fi

    case "${PWQ_EFR:-}" in
        1)    ok   "enforce_for_root=1" ;;
        0|"") warn "enforce_for_root not set — root can bypass pwquality" ;;
    esac

    if [ "${PWQ_DICT:-1}" = "0" ]; then
        warn "dictcheck=0 (dictionary words allowed)"
    fi
else
    warn "$PWQ not present (libpam-pwquality / libpwquality not installed?)"
fi

# --- 3. PAM stack ---------------------------------------------------
section 'PAM PASSWORD STACK'

for pam in /etc/pam.d/common-password /etc/pam.d/system-auth /etc/pam.d/password-auth; do
    [ -r "$pam" ] || continue
    if grep -qE '^[[:space:]]*password[[:space:]]+.*pam_pwquality' "$pam"; then
        ok "$pam references pam_pwquality"
    else
        warn "$pam does NOT reference pam_pwquality — quality rules not enforced on change"
    fi
    if grep -qE '^[[:space:]]*password[[:space:]]+.*pam_unix\.so.*remember=' "$pam"; then
        REM=$(grep -oE 'remember=[0-9]+' "$pam" | head -1 | cut -d= -f2)
        ok "$pam enforces password history (remember=$REM)"
    else
        warn "$pam has no password history (remember=) — users can reuse last password"
    fi
done

# --- 4. per-user aging (chage -l) -----------------------------------
section 'PER-USER PASSWORD AGING (chage -l)'

if [ "$(id -u)" -eq 0 ]; then
    while IFS=: read -r user _ uid _ _ _ shell; do
        case "$shell" in
            */nologin|*/false|"") continue ;;
        esac
        if [ "$user" != "root" ] && [ "$uid" -lt 1000 ]; then
            continue
        fi

        CH=$(chage -l "$user" 2>/dev/null) || continue
        U_MIN=$(echo "$CH" | awk -F: '/Minimum number of days/ {gsub(/ /,"",$2); print $2}')
        U_MAX=$(echo "$CH" | awk -F: '/Maximum number of days/ {gsub(/ /,"",$2); print $2}')
        U_LAST=$(echo "$CH" | awk -F: '/Last password change/   {sub(/^[^:]+: */,""); print}')

        line="$user (uid=$uid) min=${U_MIN:-?} max=${U_MAX:-?} last='${U_LAST:-?}'"

        case "$U_MAX" in
            ''|99999|-1)
                warn "$line — password never expires"
                ;;
            *)
                if [ "$U_MAX" -gt "$MAX_AGE_DAYS" ] 2>/dev/null; then
                    warn "$line — max > ${MAX_AGE_DAYS}d"
                elif [ "$U_MIN" = "0" ]; then
                    warn "$line — min=0"
                else
                    ok "$line"
                fi
                ;;
        esac

        if [ "${U_LAST:-}" = "never" ]; then
            fail "$user has never set a password"
        fi
    done < /etc/passwd
else
    info "skipped — chage -l requires root"
fi

# --- 5. account state ----------------------------------------------
section 'ACCOUNT STATE'

UID0=$(awk -F: '($3 == 0) {print $1}' /etc/passwd)
N=$(echo "$UID0" | wc -l)
if [ "$N" -eq 1 ] && [ "$UID0" = "root" ]; then
    ok "exactly one UID 0 account (root)"
else
    fail "multiple UID 0 accounts: $(echo "$UID0" | tr '\n' ' ')"
fi

if [ "$(id -u)" -eq 0 ] && [ -r /etc/shadow ]; then
    EMPTY=$(awk -F: '($2 == "")' /etc/shadow | cut -d: -f1)
    if [ -n "$EMPTY" ]; then
        fail "EMPTY password hash: $(echo "$EMPTY" | tr '\n' ' ')"
    else
        ok "no empty password hashes"
    fi

    UNLOCKED_SYS=$(awk -F: '($3 > 0 && $3 < 1000 && $2 !~ /^[!*]/) {print $1}' /etc/shadow)
    if [ -n "$UNLOCKED_SYS" ]; then
        warn "unlocked system accounts (UID 1-999): $(echo "$UNLOCKED_SYS" | tr '\n' ' ')"
    else
        ok "all UID 1-999 system accounts have locked password hashes"
    fi
else
    info "shadow checks skipped (need root + readable /etc/shadow)"
fi

SHELL_USERS=$(awk -F: '$7 ~ /(bash|sh|zsh|fish)$/ {print $1}' /etc/passwd | tr '\n' ' ')
info "shell-enabled accounts: $SHELL_USERS"

# --- 6. SSH config -------------------------------------------------
section 'SSH CONFIG (sshd_config)'

SSHD=/etc/ssh/sshd_config
if [ -r "$SSHD" ]; then
    PRL=$(grep -iE '^[[:space:]]*PermitRootLogin'        "$SSHD" | tail -1 | awk '{print $2}')
    PA=$(grep  -iE '^[[:space:]]*PasswordAuthentication' "$SSHD" | tail -1 | awk '{print $2}')
    PEP=$(grep -iE '^[[:space:]]*PermitEmptyPasswords'   "$SSHD" | tail -1 | awk '{print $2}')
    MAT=$(grep -iE '^[[:space:]]*MaxAuthTries'           "$SSHD" | tail -1 | awk '{print $2}')

    case "$PRL" in
        no|prohibit-password) ok   "PermitRootLogin $PRL" ;;
        yes)                  fail "PermitRootLogin yes — disable root SSH" ;;
        '')                   warn "PermitRootLogin not set (defaults to prohibit-password on modern OpenSSH)" ;;
        *)                    warn "PermitRootLogin $PRL" ;;
    esac

    case "$PA" in
        no)   ok   "PasswordAuthentication no (key-only)" ;;
        yes)  warn "PasswordAuthentication yes — consider key-only after distributing keys" ;;
        '')   info "PasswordAuthentication not set (default = yes)" ;;
        *)    info "PasswordAuthentication $PA" ;;
    esac

    case "$PEP" in
        no|'')  ok   "PermitEmptyPasswords no" ;;
        yes)    fail "PermitEmptyPasswords yes — DISABLE IMMEDIATELY" ;;
        *)      warn "PermitEmptyPasswords $PEP" ;;
    esac

    if [ -n "${MAT:-}" ]; then
        if [ "$MAT" -gt 6 ]; then
            warn "MaxAuthTries=$MAT (> 6 — eases brute force)"
        else
            ok "MaxAuthTries=$MAT"
        fi
    fi
else
    warn "$SSHD not readable"
fi

# --- 7. sudoers ----------------------------------------------------
section 'SUDOERS'

if [ "$(id -u)" -eq 0 ]; then
    NOPW=$(grep -rhE '^[^#]*NOPASSWD' /etc/sudoers /etc/sudoers.d/ 2>/dev/null)
    if [ -n "$NOPW" ]; then
        warn "NOPASSWD entries:"
        echo "$NOPW" | sed 's/^/      /' | tee -a "$OUT"
    else
        ok "no NOPASSWD entries"
    fi
else
    info "skipped (need root)"
fi

# --- summary -------------------------------------------------------
section 'SUMMARY'

TOTAL=$((PASS + WARN + FAIL))
{
    printf '\n  passed:  %d\n' "$PASS"
    printf   '  warn:    %d\n' "$WARN"
    printf   '  failed:  %d\n' "$FAIL"
    printf   '  total:   %d\n\n' "$TOTAL"
} | tee -a "$OUT"

if [ "$FAIL" -gt 0 ]; then
    echo "  [!]  $FAIL hard failures — see $OUT" | tee -a "$OUT"
elif [ "$WARN" -gt 0 ]; then
    echo "  [.]  $WARN warnings — see $OUT" | tee -a "$OUT"
else
    echo "  [+]  policy looks clean" | tee -a "$OUT"
fi

echo
echo "Full log: $OUT"
