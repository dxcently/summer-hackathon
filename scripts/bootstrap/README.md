# scripts/bootstrap/

First-run setup scripts. Run **once** per box right after T+0 (or right after WireGuard is up if you scp'd these via VPN). They install a small FOSS toolkit, create the `~/.rrintel/` workdir, and stage the triage + watchdog scripts so you can run them with one command afterward.

## The four targets (real comp topology)

| Box | OS | Script | Status |
|---|---|---|---|
| Blacklist (DB) | Debian 13 | `bootstrap-debian.sh` | included |
| Concierge (Web) | Fedora 43 | `bootstrap-fedora.sh` | included |
| Cabal (DC + DNS) | Windows Server 2022 | *manual — see below* | not scripted |
| Thebox (Firewall) | pfSense | *manual — see below* | not scripted |

Only the two Linux bootstraps ship as scripts. Windows + pfSense are short enough that a checklist beats a script (Chocolatey/`pkg` one-liners are stable enough to keep in your notes).

## Linux usage

```bash
# Blacklist (Debian 13)
sudo bash bootstrap-debian.sh

# Concierge (Fedora 43)
sudo bash bootstrap-fedora.sh
```

Optional flags (env vars before the command):

```bash
TEXLIVE=1   sudo bash bootstrap-debian.sh   # also install xelatex (~1 GB)
NO_UPDATE=1 sudo bash bootstrap-debian.sh   # skip `apt update` if you just ran it
```

**Both scripts must be run as root** (via `sudo`). They resolve the original user's home from `$SUDO_USER`, so files end up owned by you, not root.

## What gets installed

FOSS only. Nothing the CCS practice answer keys flag as prohibited (no nmap, no wireshark, no masscan).

| Category | Packages |
|---|---|
| Editors | neovim, vim, nano |
| Shell + multiplexers | tmux, screen, less |
| Version control + transfer | git, curl, wget, rsync, openssh-client |
| Networking | dnsutils/bind-utils, tcpdump, traceroute, mtr, iperf3, socat |
| Text + JSON | jq, ripgrep, fd-find (ripgrep/fd require EPEL on Alma) |
| Process + forensics | htop, btop, lsof, strace, ltrace, file, binutils, chkrootkit, rkhunter, lynis, aide |
| File utilities | tree, unzip, zip, xz, p7zip |
| Docs / PDFs | pandoc (xelatex behind `TEXLIVE=1`) |
| Python | python3, python3-pip |

Things intentionally NOT installed:

- **nmap** — flagged as prohibited in the Alma practice answer key. Skipping it on every Linux distro for consistency.
- **wireshark** — same.
- **ncat (Fedora)** — provided only via `nmap-ncat` which pulls nmap libs. Use `socat` or python sockets instead.

If you need nmap-style port scanning on your own LAN (in scope, in the lab, on your own VMs), do it from your operator laptop, not from the boxes themselves.

## What gets created

```
$HOME/.rrintel/           chmod 700, owned by you
├── bin/                   triage + watchdog scripts staged here
│   ├── linux-triage.sh
│   └── watchdog-linux.sh
├── evidence/              for binary copies, hashes, log excerpts
└── notes/                 for your shared markdown notes
```

The bootstrap *copies* the triage and watchdog scripts from their sibling repo dirs (`../triage/`, `../watchdog/`) — so for the staging step to work, you need the whole `scripts/` tree on the box, not just the bootstrap file in isolation.

Two ways to get the tree on the box:

```bash
# Option A: from your VPN'd laptop, scp the whole dir
scp -r scripts/ user@172.27.<team>.<host>:/tmp/

# Option B: tarball + paste via console
tar czf - scripts/ | base64 | xclip
# then on the box:
base64 -d | tar xzf -
```

If you only paste in `bootstrap-debian.sh` itself, the install of tools still works — the script will just print "no staging done" because the sibling dirs aren't present.

## Windows Server (manual)

Server 2016 doesn't ship with `winget`. Use Chocolatey — it's been stable on Windows servers since the 2008 days.

```powershell
# 1. Install Chocolatey (from elevated PowerShell)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = `
    [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString(
    'https://community.chocolatey.org/install.ps1'))

# 2. Install the toolkit
choco install -y `
    git `
    notepadplusplus `
    neovim `
    7zip `
    sysinternals `
    microsoft-windows-terminal `
    procmon

# 3. Sysinternals also gets a PATH entry. Reload your env to use them:
$env:Path += ';C:\ProgramData\chocolatey\bin'
```

**Sysinternals is the high-leverage install.** You get Process Explorer (`procexp`), Autoruns (`autoruns`), and TCPView (`tcpview`) — those three answer 80% of "what is this weird process / how did it persist" questions on Windows.

**Don't install:**

- Wireshark via choco (same CCS rationale as Linux — if you need packet capture on the DC, use `pktmon` which ships with Windows Server)
- Nmap-anything

**Workdir** (matches Linux convention):

```powershell
$WorkDir = Join-Path $env:USERPROFILE '.rrintel'
New-Item -ItemType Directory -Path $WorkDir -Force
(Get-Item $WorkDir).Attributes = 'Hidden'
New-Item -ItemType Directory -Path "$WorkDir\bin","$WorkDir\evidence","$WorkDir\notes" -Force
```

Then drop `windows-triage.ps1` into `$WorkDir\bin\` so it runs the same way as the Linux scripts.

## pfSense (manual)

pfSense is FreeBSD with a hard-set package list. You can install a small subset, but don't go nuts — pfSense isn't really a general-purpose admin box.

```sh
# In the pfSense shell (console option 8):
pkg install -y tmux vim-tiny less wget
```

That's it. pfSense already ships with `curl`, `git`, `htop`, `tcpdump`, `pftop`, `sockstat`, and the rest of the BSD userland. No need to install much.

**Workdir** (matches the Linux convention):

```sh
mkdir -p /root/.rrintel/bin /root/.rrintel/evidence /root/.rrintel/notes
chmod 700 /root/.rrintel
```

Then drop `pfsense-triage.sh` and `watchdog-pfsense.sh` into `/root/.rrintel/bin/`.

## After the bootstrap

The triage and watchdog scripts in `~/.rrintel/bin/` are now ready. The recommended next sequence is documented in `../README.md`, but the short version:

```bash
# 1. Baseline the box
bash ~/.rrintel/bin/linux-triage.sh

# 2. Sanity-check that the box is healthy (see triage/first-run-checks.sh)
bash <path-to-scripts>/triage/first-run-checks.sh

# 3. Start the background watchdog
nohup bash ~/.rrintel/bin/watchdog-linux.sh > /dev/null 2>&1 &

# 4. Pull baseline + log off the box for safe-keeping
scp user@172.27.<team>.<host>:~/.rrintel/triage-*.log ~/notes/
```
