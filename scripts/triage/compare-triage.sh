#!/usr/bin/env bash
# compare-triage.sh — diff two triage logs, with noise stripped.
#
# A naive `diff prev.log curr.log` lights up on every PID change,
# every "uptime" line, every transient log timestamp. This wraps
# diff with sed filters that strip:
#   - PIDs in `ps`-style output
#   - clock timestamps in the header
#   - load averages + uptime
#   - epoch numbers
#
# What's LEFT is the real signal: a user appeared, a port opened,
# a service flipped state, a file dropped into /etc.
#
# Usage:
#   bash compare-triage.sh prev.log curr.log
#   bash compare-triage.sh '~/.ecitadel/triage-blacklist-*.log'   # auto last 2
#
# Tips:
#   - Pipe through `less -R` to keep the colour
#   - Pipe through `grep -E '^[<>]'` for added/removed only

set -u
LANG=C; export LANG

usage() {
    echo "usage: $0 <prev.log> <curr.log>"
    echo "       $0 <glob>                # auto-pick the last two by mtime"
    exit 64
}

if [ "$#" -eq 1 ]; then
    # shellcheck disable=SC2206
    FILES=( $(ls -1t $1 2>/dev/null | head -2) )
    if [ "${#FILES[@]}" -lt 2 ]; then
        echo "need at least 2 matching files for: $1" >&2
        exit 1
    fi
    PREV="${FILES[1]}"
    CURR="${FILES[0]}"
elif [ "$#" -eq 2 ]; then
    PREV="$1"; CURR="$2"
else
    usage
fi

for f in "$PREV" "$CURR"; do
    [ -f "$f" ] || { echo "not a file: $f" >&2; exit 1; }
done

filter() {
    sed -E \
        -e 's/^utc:.*/utc: <REDACTED>/' \
        -e 's/^uptime:.*/uptime: <REDACTED>/' \
        -e 's/^load:.*/load: <REDACTED>/' \
        -e 's/pid=[0-9]+/pid=N/g' \
        -e 's/\bpid +[0-9]+/pid N/g' \
        -e 's/[0-9]{2}:[0-9]{2}:[0-9]{2}/HH:MM:SS/g' \
        -e 's/[A-Z][a-z]{2} [A-Z][a-z]{2} +[0-9]+/MON DAY/g' \
        -e 's/[A-Za-z]{3} +[0-9]{1,2} +[0-9]{2}:[0-9]{2}/DATE TIME/g' \
        -e 's/\b[0-9]{10,}\b/<EPOCH>/g'
}

echo "diff:"
echo "  prev: $PREV"
echo "  curr: $CURR"
echo

diff -u \
    --label "prev ($(basename "$PREV"))" \
    --label "curr ($(basename "$CURR"))" \
    <(filter < "$PREV") \
    <(filter < "$CURR") \
| sed -E \
    -e $'s/^\\+.*/\033[32m&\033[0m/' \
    -e $'s/^-.*/\033[31m&\033[0m/' \
    -e $'s/^@@.*/\033[36m&\033[0m/'
