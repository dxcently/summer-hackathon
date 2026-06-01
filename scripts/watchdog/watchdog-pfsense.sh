#!/bin/sh
# watchdog-pfsense.sh — observe-only daemon/port watchdog for pfSense
# (thebox). FreeBSD service semantics, /bin/sh only — no bash features.
#
# Mirrors watchdog-linux.sh: baseline on first tick, then log only
# DELTAS on each subsequent tick. Never restarts a service, never
# kills a process, never changes a firewall rule.
#
# Usage (pfSense console option 8 → shell):
#   nohup sh /root/watchdog-pfsense.sh > /dev/null 2>&1 &
#   # to stop:
#   kill $(cat /root/.ecitadel/watchdog-thebox.pid)
#
# Outputs (in /root/.ecitadel/ — created if missing, chmod 700):
#   watchdog-thebox-baseline.txt
#   watchdog-thebox.log
#   watchdog-thebox.pid
#
# Tunables (env vars):
#   WD_INTERVAL  seconds between ticks (default 60)

LANG=C
export LANG

HOST="thebox"
INTERVAL="${WD_INTERVAL:-60}"
WORKDIR="/root/.ecitadel"
mkdir -p "$WORKDIR"
chmod 700 "$WORKDIR" 2>/dev/null || true
BASELINE_FILE="${WORKDIR}/watchdog-${HOST}-baseline.txt"
LOG_FILE="${WORKDIR}/watchdog-${HOST}.log"
PID_FILE="${WORKDIR}/watchdog-${HOST}.pid"

# Daemons that matter on pfSense and should NOT silently disappear.
# php-fpm/lighttpd = WebGUI, sshd = our admin access, unbound/dnsmasq
# = DNS forwarder (if used), dhcpd = LAN DHCP, ntpd = clock, syslogd
# = logs. pfctl is not a daemon (it's the pf CLI) — pf itself is
# in-kernel.
WATCHED="sshd php-fpm lighttpd unbound dnsmasq dhcpd ntpd syslogd cron"

# --- single-instance pidfile ---------------------------------------
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "watchdog already running (pid $(cat "$PID_FILE"))" >&2
    exit 1
fi
echo $$ >"$PID_FILE"

TMP_A="/tmp/wd-a.$$"
TMP_B="/tmp/wd-b.$$"

cleanup() {
    log_event STOP "watchdog exiting (pid $$)"
    rm -f "$PID_FILE" "$TMP_A" "$TMP_B"
    exit 0
}
trap cleanup INT TERM HUP

# --- helpers --------------------------------------------------------
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log_event() {
    kind="$1"; shift
    printf '%s %-12s %s\n' "$(ts)" "$kind" "$*" >>"$LOG_FILE"
}

snapshot_services() {
    # FreeBSD: `service -e` lists scripts of currently-enabled services
    # that have an /etc/rc.d or /usr/local/etc/rc.d script.
    service -e 2>/dev/null | awk -F/ '{print $NF}' | sort -u
}

snapshot_ports() {
    # listening tcp + udp local ports (numeric)
    sockstat -4l 2>/dev/null \
        | awk 'NR>1 {print $6}' \
        | awk -F: '{print $NF}' \
        | grep -E '^[0-9]+$' \
        | sort -un
}

snapshot_daemons() {
    # for each watched name, print "<name> <count>"
    for name in $WATCHED; do
        c=$(pgrep -x "$name" 2>/dev/null | wc -l | tr -d ' ')
        [ -z "$c" ] && c=0
        printf '%s %s\n' "$name" "$c"
    done
}

# "first - second" line-set difference using comm
sh_diff() {
    # $1=file_left  $2=file_right  $3=mode  (gone|new)
    case "$3" in
        gone) comm -23 "$1" "$2" ;;
        new)  comm -13 "$1" "$2" ;;
    esac
}

# --- baseline -------------------------------------------------------
if [ ! -f "$BASELINE_FILE" ]; then
    {
        echo "# watchdog baseline (pfSense)"
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
        echo "## DAEMONS"
        snapshot_daemons
    } >"$BASELINE_FILE"
    log_event START "baseline written → $BASELINE_FILE (watching: $WATCHED)"
fi

BASE_SERVICES=$(awk '/^## SERVICES$/{f=1;next} /^## /{f=0} f' "$BASELINE_FILE")
BASE_PORTS=$(awk    '/^## PORTS$/{f=1;next}    /^## /{f=0} f' "$BASELINE_FILE")

PREV_SERVICES="$BASE_SERVICES"
PREV_PORTS="$BASE_PORTS"
PREV_DAEMONS=$(snapshot_daemons)

log_event START "watchdog started (pid $$, interval ${INTERVAL}s)"

# --- main loop ------------------------------------------------------
while :; do
    sleep "$INTERVAL"

    CUR_SERVICES=$(snapshot_services)
    CUR_PORTS=$(snapshot_ports)
    CUR_DAEMONS=$(snapshot_daemons)

    # --- drift vs baseline (services) ---
    printf '%s\n' "$BASE_SERVICES" >"$TMP_A"
    printf '%s\n' "$CUR_SERVICES"  >"$TMP_B"
    for s in $(sh_diff "$TMP_A" "$TMP_B" gone); do log_event DRIFT-SVC  "service no longer enabled: $s"; done
    for s in $(sh_diff "$TMP_A" "$TMP_B" new);  do log_event DRIFT-SVC+ "service newly enabled:    $s"; done

    # --- drift vs baseline (ports) ---
    printf '%s\n' "$BASE_PORTS" >"$TMP_A"
    printf '%s\n' "$CUR_PORTS"  >"$TMP_B"
    for p in $(sh_diff "$TMP_A" "$TMP_B" gone); do log_event DRIFT-PORT  "port no longer listening: $p"; done
    for p in $(sh_diff "$TMP_A" "$TMP_B" new);  do log_event DRIFT-PORT+ "port newly listening:    $p"; done

    # --- tick-to-tick (watched daemons) ---
    if [ "$PREV_DAEMONS" != "$CUR_DAEMONS" ]; then
        printf '%s\n' "$PREV_DAEMONS" >"$TMP_A"
        printf '%s\n' "$CUR_DAEMONS"  >"$TMP_B"
        diff "$TMP_A" "$TMP_B" | grep -E '^[<>]' | while read -r line; do
            log_event TICK-DAEMON "$line"
        done
    fi

    # --- tick-to-tick (services) ---
    if [ "$PREV_SERVICES" != "$CUR_SERVICES" ]; then
        printf '%s\n' "$PREV_SERVICES" >"$TMP_A"
        printf '%s\n' "$CUR_SERVICES"  >"$TMP_B"
        for s in $(sh_diff "$TMP_A" "$TMP_B" gone); do log_event TICK-SVC- "service stopped since last tick: $s"; done
        for s in $(sh_diff "$TMP_A" "$TMP_B" new);  do log_event TICK-SVC+ "service started since last tick: $s"; done
    fi

    PREV_SERVICES="$CUR_SERVICES"
    PREV_PORTS="$CUR_PORTS"
    PREV_DAEMONS="$CUR_DAEMONS"
done
