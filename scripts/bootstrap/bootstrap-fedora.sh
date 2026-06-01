#!/usr/bin/env bash
# bootstrap-fedora.sh — first-run setup for Concierge (Fedora 43,
# the real comp's web server). Installs FOSS admin + forensics
# tools, creates the ~/.ecitadel workdir, and stages the triage and
# watchdog scripts if they're sitting next to this bootstrap.
#
# Tools installed are limited to what does NOT trip CCS "prohibited
# software" checks. Notably we DO NOT install nmap, wireshark, or
# masscan — those are CCDC/CyberPatriot-flagged staples that score
# negative for being present on a defender box.
#
# Usage:
#   sudo bash bootstrap-fedora.sh
#
# Flags (via env):
#   TEXLIVE=1   also install xelatex (~1 GB) for local PDF rendering
#   EPEL=1      enable EPEL repo on Alma (Fedora doesn't need it)

set -eu
LANG=C; export LANG

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo bash $0" >&2
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
WORKDIR="${REAL_HOME}/.ecitadel"

# detect Alma vs Fedora for repo behaviour
ID_LIKE=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    ID_LIKE="${ID:-} ${ID_LIKE:-}"
fi
echo "[*] bootstrapping for ${REAL_USER} on ${ID:-unknown} (home: ${REAL_HOME})"

# ---------------------------------------------------------------
# Optional EPEL (Alma)
# ---------------------------------------------------------------
if [ "${EPEL:-0}" = "1" ] || echo "$ID_LIKE" | grep -q almalinux; then
    if ! rpm -q epel-release >/dev/null 2>&1; then
        echo "[*] installing EPEL"
        dnf install -y epel-release || true
    fi
fi

# ---------------------------------------------------------------
# Package install
# ---------------------------------------------------------------
PKGS=(
    # core admin + editors
    git curl wget ca-certificates gnupg2
    neovim vim-enhanced nano
    tmux screen less
    rsync openssh-clients

    # network + DNS (NO nmap, NO wireshark — CCS-flagged)
    bind-utils net-tools iproute
    tcpdump traceroute mtr iperf3
    # NOTE: Fedora/Alma's only netcat is nmap-ncat (which pulls nmap
    # libraries). We intentionally skip it. Use socat for the rare
    # need.
    socat

    # text + JSON
    jq

    # process / forensics
    htop lsof strace ltrace file binutils
    aide

    # tree / file utilities
    tree unzip zip xz p7zip

    # PDF + markdown
    pandoc

    # python3
    python3 python3-pip
)

# Some packages only exist via EPEL on Alma. Add them only if EPEL was
# installed (else dnf will just complain — harmless but noisy).
if rpm -q epel-release >/dev/null 2>&1; then
    PKGS+=(ripgrep fd-find btop chkrootkit rkhunter lynis)
else
    echo "[*] EPEL not installed — skipping ripgrep, fd, btop, chkrootkit, rkhunter, lynis"
    echo "    rerun with EPEL=1 to install those"
fi

if [ "${TEXLIVE:-0}" = "1" ]; then
    echo "[*] TEXLIVE=1 — adding texlive-xetex (~1 GB)"
    PKGS+=(texlive-xetex texlive-collection-fontsrecommended)
fi

echo "[*] installing ${#PKGS[@]} packages"
dnf install -y "${PKGS[@]}"

# ---------------------------------------------------------------
# Workdir
# ---------------------------------------------------------------
echo "[*] creating ${WORKDIR}"
install -d -m 700 -o "$REAL_USER" -g "$REAL_USER" "$WORKDIR"
install -d -m 700 -o "$REAL_USER" -g "$REAL_USER" "${WORKDIR}/bin"
install -d -m 700 -o "$REAL_USER" -g "$REAL_USER" "${WORKDIR}/evidence"
install -d -m 700 -o "$REAL_USER" -g "$REAL_USER" "${WORKDIR}/notes"

# ---------------------------------------------------------------
# Stage neighbor scripts
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
echo "Tools added: see /var/log/dnf.log for the install record"
echo
echo "Next steps (run as ${REAL_USER}, not root):"
echo "  cd ~/.ecitadel"
echo "  bash bin/linux-triage.sh         # capture baseline"
echo "  nohup bash bin/watchdog-linux.sh &  # background watchdog"
echo
echo "Notes:"
echo "  - All output writes to ~/.ecitadel/ (hidden, chmod 700)"
echo "  - nmap and wireshark were INTENTIONALLY skipped (CCS-flagged)"
echo "  - ncat is gated behind nmap-ncat — also skipped. Use socat."
echo "  - SELinux is on. Leave it enforcing."
