#!/usr/bin/env bash
# ir-capture.sh — full evidence pack for a single suspect PID. Run
# BEFORE you kill the process. Captures everything you need to file
# the IR PDF without going back to look at the (now-dead) process.
#
# Inspired by the CCDC/CyberPatriot "always snapshot first, kill
# second" tradition: a kill without evidence is worth zero IR
# points; an IR without a kill is worth real points.
#
# What it captures, in this order:
#   1. Process metadata (cmdline, exe path, cwd, start, user)
#   2. The binary itself (copy + SHA-256) — before /proc/<pid>/exe
#      disappears
#   3. Process environment + status + memory map
#   4. Open files + open network connections
#   5. Persistence sweep for the OWNING user (cron, authorized_keys)
#   6. Files modified in the last 7 days under the user's home
#   7. Optionally: tcpdump for 5 seconds of the process's traffic
#      (set TCPDUMP=1 — requires root)
#
# Usage:
#   bash ir-capture.sh <PID>
#   TCPDUMP=1 sudo bash ir-capture.sh <PID>
#
# Output: ~/.rrintel/evidence/<utc-ts>-pid<N>/
#
# Read-mostly. The only writes are to the evidence dir.

set -u
LANG=C; export LANG

PID="${1:-}"
case "$PID" in
    ''|*[!0-9]*) echo "usage: $0 <pid>" >&2; exit 64 ;;
esac

if [ ! -d "/proc/$PID" ]; then
    echo "no such process: pid $PID" >&2
    exit 1
fi

WORKDIR="${HOME}/.rrintel"
mkdir -p "${WORKDIR}/evidence"
chmod 700 "$WORKDIR" 2>/dev/null || true

TS=$(date -u +%Y%m%d-%H%M%SZ)
OUT="${WORKDIR}/evidence/${TS}-pid${PID}"
mkdir -p "$OUT"
chmod 700 "$OUT"

echo "[ir] capturing pid ${PID} -> ${OUT}/"

# Resolve owning user via /proc/<pid>/status
PROC_UID=$(awk '/^Uid:/{print $2}' "/proc/$PID/status" 2>/dev/null)
PROC_USER=$(getent passwd "$PROC_UID" 2>/dev/null | cut -d: -f1)
PROC_HOME=$(getent passwd "$PROC_UID" 2>/dev/null | cut -d: -f6)

# ---------------------------------------------------------------
# 1. metadata.txt
# ---------------------------------------------------------------
{
    echo "captured_utc: $(date -u)"
    echo "host:         $(hostname)"
    echo "pid:          $PID"
    echo "ppid:         $(awk '/^PPid:/{print $2}' /proc/$PID/status 2>/dev/null)"
    echo "uid:          ${PROC_UID:-unknown}"
    echo "user:         ${PROC_USER:-unknown}"
    echo "user_home:    ${PROC_HOME:-unknown}"
    echo "exe:          $(readlink -f /proc/$PID/exe 2>/dev/null)"
    echo "cwd:          $(readlink -f /proc/$PID/cwd 2>/dev/null)"
    echo "root:         $(readlink -f /proc/$PID/root 2>/dev/null)"
    echo "started:      $(stat -c %y /proc/$PID 2>/dev/null)"
    echo "cmdline:      $(tr '\0' ' ' < /proc/$PID/cmdline 2>/dev/null)"
} > "${OUT}/metadata.txt"

# ---------------------------------------------------------------
# 2. binary + hash
# ---------------------------------------------------------------
if [ -r "/proc/$PID/exe" ]; then
    cp -p "/proc/$PID/exe" "${OUT}/binary" 2>/dev/null && \
        echo "[ir] copied binary"
    if command -v sha256sum >/dev/null 2>&1 && [ -f "${OUT}/binary" ]; then
        sha256sum "${OUT}/binary" > "${OUT}/binary.sha256"
    fi
    if command -v file >/dev/null 2>&1 && [ -f "${OUT}/binary" ]; then
        file "${OUT}/binary" > "${OUT}/binary.file.txt"
    fi
fi

# ---------------------------------------------------------------
# 3. process internals (from /proc)
# ---------------------------------------------------------------
cat "/proc/$PID/status"      > "${OUT}/status.txt"  2>/dev/null
tr '\0' '\n' < "/proc/$PID/environ" > "${OUT}/environ.txt" 2>/dev/null
tr '\0' '\n' < "/proc/$PID/cmdline" > "${OUT}/cmdline.txt" 2>/dev/null
cat "/proc/$PID/maps"        > "${OUT}/maps.txt"    2>/dev/null

# ---------------------------------------------------------------
# 4. open files + network
# ---------------------------------------------------------------
if command -v lsof >/dev/null 2>&1; then
    lsof -p "$PID" -n -P > "${OUT}/open-files.txt" 2>/dev/null
fi

if command -v ss >/dev/null 2>&1; then
    {
        echo "## listening:"
        ss -tlnpe 2>/dev/null | grep -E "pid=$PID(,|\))" || echo "  (none)"
        echo
        echo "## established:"
        ss -tnpe 2>/dev/null  | grep -E "pid=$PID(,|\))" || echo "  (none)"
    } > "${OUT}/network.txt"
fi

# ---------------------------------------------------------------
# 5. persistence sweep for the owning user
# ---------------------------------------------------------------
if [ -n "${PROC_USER:-}" ]; then
    {
        echo "## crontab -l -u ${PROC_USER}"
        crontab -l -u "$PROC_USER" 2>/dev/null || echo "  (no crontab)"
        echo
        echo "## /var/spool/cron entries"
        ls -la /var/spool/cron/ 2>/dev/null
        ls -la /var/spool/cron/crontabs/ 2>/dev/null
        echo
        if [ -n "${PROC_HOME:-}" ] && [ -d "$PROC_HOME" ]; then
            echo "## ${PROC_HOME}/.ssh/authorized_keys"
            ls -la "${PROC_HOME}/.ssh/" 2>/dev/null
            [ -f "${PROC_HOME}/.ssh/authorized_keys" ] && \
                cat  "${PROC_HOME}/.ssh/authorized_keys"
            echo
            echo "## ${PROC_HOME}/.bash_history (last 50)"
            [ -f "${PROC_HOME}/.bash_history" ] && \
                tail -n 50 "${PROC_HOME}/.bash_history"
            echo
            echo "## shell rc files (suspicious tails)"
            for f in "${PROC_HOME}/.bashrc" "${PROC_HOME}/.profile" "${PROC_HOME}/.bash_profile"; do
                [ -f "$f" ] && { echo "### $f"; tail -n 20 "$f"; echo; }
            done
        fi
        echo
        echo "## systemd user units for ${PROC_USER}"
        [ -d "${PROC_HOME}/.config/systemd/user/" ] && \
            ls -la "${PROC_HOME}/.config/systemd/user/"
    } > "${OUT}/persistence-hits.txt"
fi

# ---------------------------------------------------------------
# 6. recently modified files under owning user's home
# ---------------------------------------------------------------
if [ -n "${PROC_HOME:-}" ] && [ -d "$PROC_HOME" ]; then
    find "$PROC_HOME" -mtime -7 -type f -ls 2>/dev/null \
        | sort -k 8,10 > "${OUT}/recent-files.txt"
fi

# ---------------------------------------------------------------
# 7. optional: short tcpdump of process's traffic
# ---------------------------------------------------------------
if [ "${TCPDUMP:-0}" = "1" ] && command -v tcpdump >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
        echo "[ir] tcpdump 5s on default interface"
        tcpdump -i any -nn -c 200 -w "${OUT}/traffic.pcap" \
            -G 5 -W 1 2>/dev/null || true
    else
        echo "[ir] TCPDUMP=1 set but not running as root — skipping"
    fi
fi

# ---------------------------------------------------------------
# done
# ---------------------------------------------------------------
echo
echo "[ir] evidence pack: ${OUT}"
ls -la "${OUT}/"
echo
echo "Next:"
echo "  1. Decide containment: kill -9 ${PID}  (only AFTER you have this pack)"
echo "  2. Disable persistence found in: ${OUT}/persistence-hits.txt"
echo "  3. File the IR PDF using templates/ir-report.md"
echo "     - Hash:    ${OUT}/binary.sha256"
echo "     - Cmdline: ${OUT}/cmdline.txt"
echo "     - Network: ${OUT}/network.txt"
