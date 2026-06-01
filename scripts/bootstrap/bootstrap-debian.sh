#!/usr/bin/env bash
# bootstrap-debian.sh — first-run setup for Debian-family boxes
# (Debian 13 / Linux Mint 21). Installs FOSS admin + forensics tools,
# creates the ~/.ecitadel workdir, and stages the triage/watchdog
# scripts if they're sitting next to this bootstrap.
#
# Tools installed are limited to what does NOT trip CCS "prohibited
# software" checks. Notably we DO NOT install nmap, wireshark, or
# masscan — those are flagged in the practice round answer keys.
#
# Usage:
#   sudo bash bootstrap-debian.sh
#
# Flags (via env):
#   TEXLIVE=1   also install xelatex (~1 GB) for local PDF rendering
#   NO_UPDATE=1 skip `apt update` (use if you already updated)

set -eu
LANG=C; export LANG

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo bash $0" >&2
    exit 1
fi

# resolve the real user's home, even when invoked via sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
WORKDIR="${REAL_HOME}/.ecitadel"

echo "[*] bootstrapping for ${REAL_USER} (home: ${REAL_HOME})"

# ---------------------------------------------------------------
# Package install
# ---------------------------------------------------------------
PKGS=(
    # core admin + editors
    git curl wget ca-certificates gnupg
    neovim vim nano
    tmux screen less
    rsync openssh-client

    # network + DNS (NO nmap, NO wireshark — CCS-flagged)
    dnsutils net-tools iproute2
    tcpdump traceroute mtr-tiny iperf3
    netcat-openbsd          # bsd netcat — safe, no nmap-base baggage
    socat

    # text + JSON
    jq ripgrep fd-find

    # process / forensics
    htop btop lsof strace ltrace file binutils
    chkrootkit rkhunter lynis aide

    # tree / file utilities
    tree unzip zip xz-utils p7zip-full

    # PDF + markdown (light — full xelatex behind flag)
    pandoc

    # python3 for ad-hoc scripts
    python3 python3-pip
)

if [ "${TEXLIVE:-0}" = "1" ]; then
    echo "[*] TEXLIVE=1 — adding texlive-xetex (~1 GB)"
    PKGS+=(texlive-xetex texlive-fonts-recommended)
fi

if [ "${NO_UPDATE:-0}" != "1" ]; then
    echo "[*] apt update"
    apt-get update -y
fi

echo "[*] installing ${#PKGS[@]} packages"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PKGS[@]}"

# ---------------------------------------------------------------
# Workdir
# ---------------------------------------------------------------
echo "[*] creating ${WORKDIR}"
install -d -m 700 -o "$REAL_USER" -g "$REAL_USER" "$WORKDIR"
install -d -m 700 -o "$REAL_USER" -g "$REAL_USER" "${WORKDIR}/bin"
install -d -m 700 -o "$REAL_USER" -g "$REAL_USER" "${WORKDIR}/evidence"
install -d -m 700 -o "$REAL_USER" -g "$REAL_USER" "${WORKDIR}/notes"

# ---------------------------------------------------------------
# Stage neighbor scripts (triage + watchdog) if present
# ---------------------------------------------------------------
BOOTSTRAP_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${BOOTSTRAP_DIR}/.." && pwd 2>/dev/null || true)"

stage() {
    local src="$1" dst="$2"
    if [ -f "$src" ]; then
        install -m 750 -o "$REAL_USER" -g "$REAL_USER" "$src" "$dst"
        echo "    staged: $(basename "$src")"
    fi
}

if [ -d "${SCRIPTS_ROOT}" ]; then
    echo "[*] staging triage + watchdog scripts into ${WORKDIR}/bin"
    stage "${SCRIPTS_ROOT}/triage/linux-triage.sh"   "${WORKDIR}/bin/linux-triage.sh"
    stage "${SCRIPTS_ROOT}/watchdog/watchdog-linux.sh" "${WORKDIR}/bin/watchdog-linux.sh"
fi

# ---------------------------------------------------------------
# Done
# ---------------------------------------------------------------
echo
echo "[done] bootstrap complete"
echo
echo "Workdir:     ${WORKDIR}/"
echo "Tools added: see /var/log/apt/history.log for the install record"
echo
echo "Next steps (run as ${REAL_USER}, not root):"
echo "  cd ~/.ecitadel"
echo "  bash bin/linux-triage.sh         # capture baseline"
echo "  nohup bash bin/watchdog-linux.sh &  # background watchdog"
echo
echo "Notes:"
echo "  - All output writes to ~/.ecitadel/ (hidden, chmod 700)"
echo "  - nmap and wireshark were INTENTIONALLY skipped (CCS-flagged)"
echo "  - For ad-hoc port checks, use: ss -tlnp + nc -zv <host> <port>"
