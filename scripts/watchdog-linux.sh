#!/usr/bin/env bash
# watchdog-linux.sh — observe-only process/service/port watchdog for
# Blacklist (Debian 13) and Concierge (Fedora 43).
#
# What it does:
#   - On first tick: capture a BASELINE of running systemd services,
#     TCP/UDP listeners, and per-process counts for important daemons.
#   - On each subsequent tick (default every 60 s):
#       * compare current state to BASELINE  → log "drift" events
#       * compare current state to PREV tick → log "tick delta" events
#   - Only logs DELTAS. No noise when nothing changes.
#
# What it does NOT do:
#   - Does not restart services
#   - Does not kill processes
#   - Does not change firewall rules
#   - Does not modify any system state
#
# Usage:
#   nohup sudo bash watchdog-linux.sh > /dev/null 2>&1 &
#   # to stop:
#   kill $(cat ~/.ecitadel/watchdog-$(hostname).pid)
#
# Outputs (in ~/.ecitadel/ — created if missing, chmod 700):
#   watchdog-<host>-baseline.txt   one-shot snapshot from first tick
#   watchdog-<host>.log            append-only deltas, one event per line
#   watchdog-<host>.pid            process id (so you can stop it cleanly)
#
# Tunables (env vars):
#   WD_INTERVAL  seconds between ticks (default 60)
#   WD_WATCH     space-separated list of service basenames to track
#                (default: auto-detect on first tick)

set -u
LANG=C
export LANG

HOST="$(hostname)"
INTERVAL="${WD_INTERVAL:-60}"
WORKDIR="${HOME}/.ecitadel"
mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR" 2>/dev/null || true
BASELINE_FILE="${WORKDIR}/watchdog-${HOST}-baseline.txt"
LOG_FILE="${WORKDIR}/watchdog-${HOST}.log"
PID_FILE="${WORKDIR}/watchdog-${HOST}.pid"

# --- pidfile / single-instance --------------------------------------
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "watchdog already running (pid $(cat "$PID_FILE"))" >&2
    exit 1
fi
echo $$ >"$PID_FILE"

cleanup() {
    log_event STOP "watchdog exiting (pid $$)"
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup INT TERM

# --- helpers --------------------------------------------------------
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log_event() {
    # usage: log_event EVENT_TYPE message...
    local kind="$1"; shift
    printf '%s %-12s %s\n' "$(ts)" "$kind" "$*" >>"$LOG_FILE"
}

snapshot_services() {
    # active systemd services (one name per line)
    systemctl list-units --type=service --state=active --no-pager --no-legend 2>/dev/null \
        | awk '{print $1}' | sed 's/\.service$//' | sort -u
}

snapshot_ports() {
    # listening tcp + udp local ports
    {
        ss -tln 2>/dev/null | awk 'NR>1 {print "tcp/" $4}'
        ss -uln 2>/dev/null | awk 'NR>1 {print "udp/" $4}'
    } | sed -E 's/.*:([0-9]+)$/\1/' | sort -un
}

snapshot_proc_counts() {
    # for each watched name, print "<name> <count>"
    local name
    for name in $WATCHED; do
        local c
        c=$(pgrep -c -x "$name" 2>/dev/null || echo 0)
        printf '%s %s\n' "$name" "$c"
    done
}

# --- pick watched processes ----------------------------------------
# If WD_WATCH is set, use that. Otherwise auto-pick a sensible set
# based on which services are present on the box.
if [ -n "${WD_WATCH:-}" ]; then
    WATCHED="$WD_WATCH"
else
    WATCHED=""
    for cand in sshd systemd-journald rsyslogd cron crond auditd \
                postgres mysqld mariadbd \
                nginx httpd apache2 php-fpm \
                sssd realmd \
                ufw firewalld nftables \
                fail2ban-server; do
        if pgrep -x "$cand" >/dev/null 2>&1; then
            WATCHED="$WATCHED $cand"
        fi
    done
    WATCHED="${WATCHED# }"
fi
[ -z "$WATCHED" ] && WATCHED="sshd"

# --- baseline -------------------------------------------------------
if [ ! -f "$BASELINE_FILE" ]; then
    {
        echo "# watchdog baseline"
        echo "host:     $HOST"
        echo "utc:      $(ts)"
        echo "interval: ${INTERVAL}s"
        echo "watched:  $WATCHED"
        echo
        echo "## SERVICES"
        snapshot_services
        echo
        echo "## PORTS"
        snapshot_ports
        echo
        echo "## PROC_COUNTS"
        snapshot_proc_counts
    } >"$BASELINE_FILE"
    log_event START "baseline written → $BASELINE_FILE (watching: $WATCHED)"
fi

# Pull baseline lists from the file into vars
BASE_SERVICES="$(awk '/^## SERVICES$/{f=1;next} /^## /{f=0} f' "$BASELINE_FILE")"
BASE_PORTS="$(awk    '/^## PORTS$/{f=1;next}    /^## /{f=0} f' "$BASELINE_FILE")"

PREV_SERVICES="$BASE_SERVICES"
PREV_PORTS="$BASE_PORTS"
PREV_PROC="$(snapshot_proc_counts)"

# --- main loop ------------------------------------------------------
log_event START "watchdog started (pid $$, interval ${INTERVAL}s)"

while :; do
    sleep "$INTERVAL"

    CUR_SERVICES="$(snapshot_services)"
    CUR_PORTS="$(snapshot_ports)"
    CUR_PROC="$(snapshot_proc_counts)"

    # --- drift from baseline ---
    s_gone="$(comm -23 <(printf '%s\n' "$BASE_SERVICES") <(printf '%s\n' "$CUR_SERVICES"))"
    s_new="$(comm  -13 <(printf '%s\n' "$BASE_SERVICES") <(printf '%s\n' "$CUR_SERVICES"))"
    [ -n "$s_gone" ] && for s in $s_gone; do log_event DRIFT-SVC  "service no longer active: $s"; done
    [ -n "$s_new"  ] && for s in $s_new;  do log_event DRIFT-SVC+ "service newly active:    $s"; done

    p_gone="$(comm -23 <(printf '%s\n' "$BASE_PORTS") <(printf '%s\n' "$CUR_PORTS"))"
    p_new="$(comm  -13 <(printf '%s\n' "$BASE_PORTS") <(printf '%s\n' "$CUR_PORTS"))"
    [ -n "$p_gone" ] && for p in $p_gone; do log_event DRIFT-PORT  "port no longer listening: $p"; done
    [ -n "$p_new"  ] && for p in $p_new;  do log_event DRIFT-PORT+ "port newly listening:    $p"; done

    # --- tick-to-tick delta (catches flaps) ---
    if [ "$PREV_SERVICES" != "$CUR_SERVICES" ]; then
        ts_gone="$(comm -23 <(printf '%s\n' "$PREV_SERVICES") <(printf '%s\n' "$CUR_SERVICES"))"
        ts_new="$(comm  -13 <(printf '%s\n' "$PREV_SERVICES") <(printf '%s\n' "$CUR_SERVICES"))"
        [ -n "$ts_gone" ] && for s in $ts_gone; do log_event TICK-SVC- "service stopped since last tick: $s"; done
        [ -n "$ts_new"  ] && for s in $ts_new;  do log_event TICK-SVC+ "service started since last tick: $s"; done
    fi

    if [ "$PREV_PROC" != "$CUR_PROC" ]; then
        diff <(printf '%s\n' "$PREV_PROC") <(printf '%s\n' "$CUR_PROC") \
            | awk '/^[<>]/ {print}' \
            | while read -r line; do
                log_event TICK-PROC "$line"
              done
    fi

    PREV_SERVICES="$CUR_SERVICES"
    PREV_PORTS="$CUR_PORTS"
    PREV_PROC="$CUR_PROC"
done
