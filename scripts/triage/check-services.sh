#!/usr/bin/env bash
# check-services.sh — verify every scored service is reachable +
# responding. Designed for repeated re-runs during the round, so it
# completes in ~3 seconds and prints one pass/fail line per service.
#
# Run from your VPN'd operator laptop (probes via EXTERNAL IPs the
# way the scoring engine does) OR from inside the network (override
# the BASE env var to test internal reach instead).
#
# Use this when:
#   - You just made a config change and want to verify before the
#     scoreboard updates (~5 min lag)
#   - The scoreboard is red and you want to know if it's *actually*
#     down vs scoreboard lag
#   - You want a pre-comp baseline of "everything green"
#
# Usage:
#   bash check-services.sh 17               # team 17, external (172.27.17.x)
#   BASE=172.21.0 bash check-services.sh    # internal (172.21.0.x), no team arg
#
# Defaults match the real comp topology (blacklist/concierge/cabal).
# Override SERVICES if you're testing the practice round or a
# different layout.

set -u
LANG=C; export LANG

if [ -t 1 ]; then
    G="$(printf '\033[32m')"; R="$(printf '\033[31m')"
    Y="$(printf '\033[33m')"; N="$(printf '\033[0m')"
else
    G=""; R=""; Y=""; N=""
fi

ok()   { printf '  %s[ ok ]%s  %-25s %s\n' "$G" "$N" "$1" "$2"; }
warn() { printf '  %s[warn]%s  %-25s %s\n' "$Y" "$N" "$1" "$2"; }
fail() { printf '  %s[FAIL]%s  %s%-25s%s %s\n' "$R" "$N" "$R" "$1" "$N" "$2"; }

# --- config ---------------------------------------------------------
if [ -n "${BASE:-}" ]; then
    PREFIX="$BASE"
    LABEL="internal"
elif [ "$#" -ge 1 ]; then
    case "$1" in
        ''|*[!0-9]*) echo "team must be a number" >&2; exit 64 ;;
    esac
    PREFIX="172.27.$1"
    LABEL="team $1 external"
else
    echo "usage: $0 <team-number>      # external probe (172.27.<team>.x)"
    echo "       BASE=172.21.0 $0      # internal probe"
    exit 64
fi

DB="${PREFIX}.101"
WEB="${PREFIX}.102"
DC="${PREFIX}.103"

# Each entry: "label host port [probe-type]"
# probe-type: tcp (default), http, https, dns
SERVICES=(
    "blacklist SSH    $DB  22 tcp"
    "blacklist DB-pg  $DB  5432 tcp"
    "blacklist DB-my  $DB  3306 tcp"
    "concierge SSH    $WEB 22 tcp"
    "concierge HTTP   $WEB 80 http"
    "concierge HTTPS  $WEB 443 https"
    "cabal DNS        $DC  53 dns"
    "cabal LDAP       $DC  389 tcp"
    "cabal LDAPS      $DC  636 tcp"
    "cabal Kerberos   $DC  88 tcp"
    "cabal SMB        $DC  445 tcp"
    "cabal RDP        $DC  3389 tcp"
)

printf '\n  utc: %s   target: %s (%s)\n\n' \
    "$(date -u +%H:%M:%SZ)" "$PREFIX.x" "$LABEL"

# --- probes ---------------------------------------------------------
for entry in "${SERVICES[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    label="$1 $2"; host="$3"; port="$4"; probe="${5:-tcp}"

    case "$probe" in
        tcp)
            if timeout 2 bash -c "(echo > /dev/tcp/$host/$port) >/dev/null 2>&1"; then
                ok "$label" "$host:$port open"
            else
                fail "$label" "$host:$port closed/filtered"
            fi
            ;;
        http|https)
            scheme="$probe"
            code=$(curl -ks --max-time 3 -o /dev/null \
                -w '%{http_code}' "$scheme://$host/" 2>/dev/null)
            case "$code" in
                200|301|302|401|403)
                    ok "$label" "$scheme://$host/ → $code" ;;
                000)
                    fail "$label" "$scheme://$host/ unreachable" ;;
                *)
                    warn "$label" "$scheme://$host/ → $code" ;;
            esac
            ;;
        dns)
            if command -v dig >/dev/null 2>&1; then
                if dig +short +time=2 +tries=1 "@$host" rrintel.internal 2>/dev/null | grep -qE '^[0-9]'; then
                    ok "$label" "$host:$port answers rrintel.internal"
                else
                    fail "$label" "$host:$port no answer"
                fi
            else
                warn "$label" "dig not installed"
            fi
            ;;
    esac
done

echo
echo "  (run again in ~5 min — scoreboard lags this view by 2-3 min)"
