# scripts/

Read-only operator toolkit for the eCitadel round. Three lifecycle dirs:

```
scripts/
├── bootstrap/   # one-shot setup (install FOSS toolkit, stage scripts)
├── triage/     # state capture + re-checks + IR evidence
├── watchdog/   # background delta loggers
└── harden/     # APPLY hardening changes (Windows only, opt-in, idempotent)
```

**`bootstrap/`, `triage/`, `watchdog/` are read-only.** No service restarts, no killed processes, no firewall edits, no password changes. Everything is `cat` / `ls` / `Get-*` / `pfctl -s*` / `dig` / `ping`. Safe to run repeatedly under scoring pressure.

**`harden/` is the only place that writes state**, and only when the operator opts in. Each script supports `-DryRun`, verifies every change after applying, is idempotent on re-run, and refuses operations that would break scored services (no firewall edits, no mass password reset, no RDP disable, no Administrator disable without a verified replacement admin).

**All scripts write to a hidden workdir** (`~/.ecitadel/` on Linux/laptop, `/root/.ecitadel/` on pfSense, `%USERPROFILE%\.ecitadel\` on Windows). The dir is created `chmod 700` so a casual `ls` doesn't expose your evidence to anyone who shoulder-surfs the console. On Windows the folder is also marked Hidden. To inspect: `ls -la ~/.ecitadel/`.

---

## Run guide

The scripts are designed to be run in this order. Each phase produces an artifact the next phase relies on (or compares against).

### Phase 0 — pre-comp (laptop, day before)

```bash
# from your operator laptop, BEFORE comp day:
bash scripts/triage/check-services.sh 17     # team 17 — should print all FAIL (boxes not up yet)
# verify the script runs cleanly. You don't want to debug bash on game day.
```

### Phase 1 — bootstrap (T+0 to T+5 per box)

One-shot. Installs toolkit, creates `~/.ecitadel/{bin,evidence,notes}`, copies `linux-triage.sh` + `watchdog-linux.sh` into `~/.ecitadel/bin/`.

```bash
# Blacklist (Debian 13)
sudo bash scripts/bootstrap/bootstrap-debian.sh

# Concierge (Fedora 43)
sudo bash scripts/bootstrap/bootstrap-fedora.sh
```

Windows + pfSense are manual checklists — see `scripts/bootstrap/README.md`.

### Phase 2 — first-run health (T+5 to T+10 per box)

60-second sanity sweep. Tells you whether the box is even in a *useful* starting state before you spend 10 min on a full triage.

```bash
bash scripts/triage/first-run-checks.sh
# → ~/.ecitadel/firstrun-<host>-<ts>.log + pass/warn/fail summary
```

If `first-run-checks.sh` reports hard failures (DC unreachable, clock skew > 5min, root disk > 90%) — fix those first. A full triage on a broken box just produces a broken log.

### Phase 3 — baseline triage (T+10 to T+25 per box)

This is the **ground-truth snapshot**. Every later diff is against this run.

```bash
# Linux boxes
sudo bash ~/.ecitadel/bin/linux-triage.sh           # or scripts/triage/linux-triage.sh

# Windows (Cabal)
powershell.exe -ExecutionPolicy Bypass -File scripts/triage/windows-triage.ps1

# pfSense
sh scripts/triage/pfsense-triage.sh

# From your VPN'd laptop (external POV)
bash scripts/triage/external-check.sh 17
```

Pull all four logs off the boxes onto your laptop as soon as they're done. The boxes can be reverted; your laptop can't.

### Phase 4 — watchdog (T+25 onward, set-and-forget)

Background daemon. Captures baseline, then logs only **deltas** every 60s.

```bash
# Linux
nohup sudo bash ~/.ecitadel/bin/watchdog-linux.sh > /dev/null 2>&1 &

# pfSense
nohup sh scripts/watchdog/watchdog-pfsense.sh > /dev/null 2>&1 &
```

No Windows watchdog — see "Why no Windows watchdog?" below.

### Phase 5 — periodic checks (every 5-10 min, all round)

Short scripts. Re-run them whenever the scoreboard flips or you make a change.

```bash
# Is the box even on the LAN?  (~2s)
bash scripts/triage/check-network.sh

# Are scored services responding?  (~3s, run from laptop)
bash scripts/triage/check-services.sh 17
```

### Phase 6 — periodic re-triage (every ~60 min)

Re-run the full triage and diff against the last one. The watchdog catches state changes in real time; the periodic re-triage catches everything the watchdog doesn't monitor (file changes in `/etc`, new sudoers entries, new SUID binaries).

```bash
sudo bash ~/.ecitadel/bin/linux-triage.sh
bash scripts/triage/compare-triage.sh '~/.ecitadel/triage-blacklist-*.log'
```

### Phase 7 — IR capture (only when you find something)

You found a suspicious PID. Snapshot evidence **before** you kill it.

```bash
sudo bash scripts/triage/ir-capture.sh <PID>
# → ~/.ecitadel/evidence/<utc-ts>-pid<N>/  (binary, hash, network, persistence, recent files)

# THEN, after you have the evidence pack:
sudo kill -9 <PID>
```

---

## Scripts reference

### bootstrap/

#### `bootstrap-debian.sh` / `bootstrap-fedora.sh`

Install a FOSS toolkit, create `~/.ecitadel/{bin,evidence,notes}`, stage triage + watchdog scripts. **Both must be run as root via `sudo`.** Resolves `$SUDO_USER` to own files correctly. See `scripts/bootstrap/README.md` for the full package list, optional flags (`TEXLIVE=1`, `NO_UPDATE=1`), and the Windows + pfSense manual checklists.

### triage/

#### `linux-triage.sh`

Read-only state capture for **Blacklist (Debian 13)** and **Concierge (Fedora 43)**. Auto-detects distro for firewall (`ufw` vs `firewalld` vs `nftables`) and package manager (`dpkg` vs `rpm`).

```bash
sudo bash linux-triage.sh
# → ~/.ecitadel/triage-<hostname>-<utc-ts>.log
```

Captures: users (`/etc/passwd`, `/etc/shadow`, sudoers), network (interfaces, listeners, routes), services + cron + systemd timers, persistence vectors (SUID/SGID, all `authorized_keys`, profile.d, systemd unit files), recently modified files in `/etc`, `/var/www`, `/tmp`, processes, web artifacts (webshell candidates, oversized PHP), DB listeners, SSSD/AD-join state, SELinux/AppArmor, firewall rules, sshd_config, package install log, recent journal errors, recent logins.

#### `windows-triage.ps1`

Read-only state capture for **Cabal (Windows Server 2022 / DC + DNS for `rrintel.internal`)**.

```powershell
powershell.exe -ExecutionPolicy Bypass -File windows-triage.ps1
# → %USERPROFILE%\.ecitadel\triage-<computer>-<utc-ts>.log
```

Captures: local users + groups, all AD users (with whenCreated, last logon, password set), AD users created in last 7 days, Domain Admins / Enterprise Admins / Schema Admins / Administrators / Account Operators membership, AD computers, accounts with non-expiring passwords, accounts with SPNs (Kerberoast surface), running services, non-Microsoft auto-start services, non-Microsoft scheduled tasks, tasks running as SYSTEM, HKLM/HKCU Run keys + RunOnce, Win32_StartupCommand, WMI event filters + consumers + bindings, network (IP config, listeners, established connections), firewall profile state, DNS server zones + `rrintel.internal` records, SMB shares + sessions + config (SMBv1 status), interactive sessions, Defender status + preferences + threat history, recent Security events (4624 logon, 4625 failed logon, 4720 user-created, 4732/4756 group add, 7045 service install), recently modified files in `C:\ProgramData`, `C:\Users\Public`, `C:\Windows\Temp`, audit policy.

#### `pfsense-triage.sh`

Read-only state capture for **pfSense (thebox)**. Uses pfSense's `/bin/sh` — no bash features. Uses `pfctl`, `sockstat`, direct reads of `/cf/conf/config.xml`.

```sh
# pfSense console menu → 8 (Shell), then:
sh /root/pfsense-triage.sh
# → /root/.ecitadel/triage-thebox-<utc-ts>.log
```

Captures: interfaces (ifconfig, stats), pf rules + NAT rules + state table summary + first 100 states, routing table, local TCP/UDP listeners (sockstat), installed packages + running services + daemons, admin users from `config.xml`, NAT 1:1 + inbound rdr rules, recent webGUI/SSH auth events, last 100 firewall log lines, last 100 system log lines.

#### `external-check.sh`

Probes scored services **from outside pfSense**, the way the scoring engine does. Run from your VPN'd operator laptop. Probes ONLY your team's external /24 — never another team, never red team.

```bash
bash external-check.sh 17        # replace 17 with your team number
# → ~/.ecitadel/external-check-<utc-ts>.log
```

Checks: ICMP reachability for all three hosts; DNS from Cabal (A/SOA/NS for `rrintel.internal`, `_ldap._tcp` SRV, `_kerberos._tcp` SRV, reverse); SSH on .101/.102/.103; HTTP+HTTPS on Concierge (status, headers, TLS cert); DB ports on Blacklist (5432/3306/1433); AD/LDAP ports on Cabal (389/636/88/3389/445/53). Ends with one-table pass/fail summary.

> **Important:** `external-check.sh` returning `HTTPS OK (200)` is *necessary but not sufficient*. The scoring engine logs in and exercises functionality — a 200 from a placeholder page still scores zero. After this script reports green, hit the app in your browser and do one real login action.

#### `first-run-checks.sh`

60-second health + connectivity sanity sweep. Run **right after bootstrap, before the full triage**. Categorical pass/warn/fail output + a per-run log.

```bash
bash first-run-checks.sh
GW=172.21.0.150 DC=172.21.0.103 DOMAIN=rrintel.internal bash first-run-checks.sh
# → ~/.ecitadel/firstrun-<host>-<ts>.log
```

Checks: gateway + DC + internet ping; DNS forward + AD `_ldap._tcp` SRV; NTP sync state and clock skew vs internet (Kerberos breaks > 5 min); root disk + memory + load; available **security** updates (apt/dnf); TLS cert expiry for HTTPS scored services; hostname / FQDN / primary IP / reverse DNS sanity. Tunables: `GW`, `DC`, `DOMAIN`.

#### `check-network.sh`

Fast network-only sweep. ~2 seconds. Designed for *repeated* runs throughout the round without filling the workdir with logs — output goes to stdout only, no log file written.

```bash
bash check-network.sh
GW=172.21.0.150 DC=172.21.0.103 bash check-network.sh
QUIET=1 bash check-network.sh        # only show warns + fails
```

Checks: gateway ping, DC ping, internet egress, DNS A + AD SRV, TCP probes on DC ports `53/88/389/445/636`, local listener count. Use this when the scoreboard flips and you need to isolate "box off the LAN" vs "service broken".

#### `check-services.sh`

Fast scored-services sweep. ~3 seconds. Probes every scored port and protocol-checks HTTP/HTTPS/DNS where it can. Run from the laptop (external POV) or override `BASE` for internal POV.

```bash
bash check-services.sh 17              # team 17, external (172.27.17.x)
BASE=172.21.0 bash check-services.sh   # internal (172.21.0.x)
```

Probes: blacklist SSH/Postgres/MySQL; concierge SSH/HTTP/HTTPS (real curl with status codes); cabal DNS (real `dig rrintel.internal`)/LDAP/LDAPS/Kerberos/SMB/RDP. The scoreboard lags this view by 2-3 min — when the script says green, give the scoring engine one more cycle before declaring victory.

#### `check-policy-linux.sh`

Read-only audit of password policy + account state on **Blacklist / Concierge**. Same pass/warn/fail format as `first-run-checks.sh`. Writes one log per run.

```bash
sudo bash check-policy-linux.sh
HARD_MIN_LEN=8 MIN_LEN=16 MAX_AGE_DAYS=60 sudo bash check-policy-linux.sh
# → ~/.ecitadel/policy-<host>-<ts>.log
```

Flags: `PASS_MIN_DAYS=0` (allows immediate cycling after a forced reset); `PASS_MIN_LEN` below threshold (default FAIL < 6, WARN < 14); `PASS_MAX_DAYS` > 90; `pwquality.conf` minlen + complexity credits + `enforce_for_root`; PAM stack actually wires in `pam_pwquality` and `remember=` for history; per-user `chage -l` for never-expiring passwords and `min=0`; multiple UID 0 accounts; **empty password hashes in `/etc/shadow`**; unlocked system accounts (UID 1–999 without `!`/`*` in shadow); `sshd_config` (`PermitRootLogin`, `PasswordAuthentication`, `PermitEmptyPasswords`, `MaxAuthTries`); sudoers `NOPASSWD` entries.

Tunables (env): `HARD_MIN_LEN` (FAIL threshold, default 6), `MIN_LEN` (WARN threshold, default 14), `MAX_AGE_DAYS` (default 90), `MIN_AGE_DAYS` (default 1).

Run after the baseline triage, then again after any user/policy inject so you can prove the change took.

#### `check-policy-windows.ps1`

Same idea for **Cabal**. Audits local SAM policy via `net accounts`, AD default domain password policy via `Get-ADDefaultDomainPasswordPolicy`, and the state of the built-in `Administrator` (RID 500) + `Guest` (RID 501) accounts on both local SAM and AD.

```powershell
powershell.exe -ExecutionPolicy Bypass -File check-policy-windows.ps1
.\check-policy-windows.ps1 -MinLen 16 -HardMinLen 8 -MaxAgeDays 60
# → %USERPROFILE%\.ecitadel\policy-<COMPUTERNAME>-<ts>.log
```

Flags: `MinimumPasswordLength` below threshold (default FAIL < 6, WARN < 14); `MaximumPasswordAge` > 90; `MinimumPasswordAge` < 1 (allows immediate cycling); `LockoutThreshold` = 0 (no lockout — brute force open) or > 10; `PasswordHistoryLength` < 5; AD: `ComplexityEnabled=False`, `ReversibleEncryptionEnabled=True` (crypto backdoor); **Administrator (RID 500) enabled** — should be disabled and renamed; **Guest (RID 501) enabled** — should be disabled; `DefaultAccount` (RID 503) enabled; any local account with `PasswordRequired=False`; any enabled account with `PasswordNeverExpires`; `krbtgt` password age > 180 days; AD users with `PasswordNotRequired=True`; Domain Admins / Enterprise Admins membership listings; LSA `LimitBlankPasswordUse=0` and `NoLMHash=0`.

Parameters: `-MinLen` (WARN, default 14), `-HardMinLen` (FAIL, default 6), `-MaxAgeDays` (default 90), `-MinAgeDays` (default 1).

Some checks require AD module / DC — those skip gracefully on member servers.

#### `compare-triage.sh`

Diffs two triage logs with noise stripped (PIDs, timestamps, uptime, load averages, epoch numbers). What's left is real signal — a new user, a new port, a service flip, a file change in `/etc`. Color-coded.

```bash
bash compare-triage.sh prev.log curr.log
bash compare-triage.sh '~/.ecitadel/triage-blacklist-*.log'   # auto-pick last 2 by mtime

# Useful pipes:
bash compare-triage.sh '...glob...' | less -R                 # keep colour
bash compare-triage.sh '...glob...' | grep -E '^[<>]'         # added/removed only
```

#### `ir-capture.sh`

Full evidence pack for a single suspect PID. **Run before you kill the process.** A kill without evidence is worth zero IR points; an IR PDF without a kill is worth real points — and you can't grep the PID after it's dead.

```bash
bash ir-capture.sh <PID>
TCPDUMP=1 sudo bash ir-capture.sh <PID>     # also capture 5s of pcap (needs root)
# → ~/.ecitadel/evidence/<utc-ts>-pid<N>/
```

Captures, in order:

1. **Process metadata** (`metadata.txt`) — cmdline, exe, cwd, root, ppid, uid, owning user + home, start time.
2. **The binary itself** (`binary` + `binary.sha256` + `binary.file.txt`) — copied from `/proc/<pid>/exe` before the kernel forgets.
3. **Process internals** (`status.txt`, `environ.txt`, `cmdline.txt`, `maps.txt`) — full `/proc/<pid>` state.
4. **Open files + network** (`open-files.txt`, `network.txt`) — `lsof -p`, `ss -tlnpe` / `ss -tnpe` filtered to this PID.
5. **Persistence sweep for the owning user** (`persistence-hits.txt`) — that user's crontab, `/var/spool/cron`, `~/.ssh/authorized_keys`, last 50 lines of `~/.bash_history`, tail of `.bashrc` / `.profile`, systemd user units.
6. **Recent file changes** (`recent-files.txt`) — `find $HOME -mtime -7 -type f -ls`.
7. **Optional pcap** (`traffic.pcap`) — 5 seconds, 200 packets, `tcpdump -i any`, root-only via `TCPDUMP=1`.

After the script finishes, the printed "Next" block tells you exactly what to do (`kill -9`, disable persistence, file the IR PDF using `templates/ir-report.md` referencing the hash, cmdline, and network files).

### watchdog/

#### `watchdog-linux.sh`

Observe-only background daemon for **Blacklist + Concierge**. Captures a baseline of running services, listening ports, and per-process counts on first tick. Each subsequent tick (default 60s) compares against baseline + previous tick and logs only **deltas**. Does not restart anything. Does not kill anything.

```bash
nohup sudo bash watchdog-linux.sh > /dev/null 2>&1 &

tail -f ~/.ecitadel/watchdog-$(hostname).log

kill $(cat ~/.ecitadel/watchdog-$(hostname).pid)
```

Outputs three files in `~/.ecitadel/`:

- `watchdog-<host>-baseline.txt` — snapshot from first tick
- `watchdog-<host>.log` — append-only event log, one line per change
- `watchdog-<host>.pid` — pidfile

Event types:

| Event | Meaning |
|---|---|
| `START` / `STOP` | Watchdog lifecycle |
| `DRIFT-SVC` / `DRIFT-SVC+` | A service active at baseline is now inactive (or vice versa) |
| `DRIFT-PORT` / `DRIFT-PORT+` | A port listening at baseline is no longer listening (or new) |
| `TICK-SVC-` / `TICK-SVC+` | A service changed state since the *previous* tick (catches flaps) |
| `TICK-PROC` | A watched daemon's process count changed |

Tunables via environment variable:

```bash
WD_INTERVAL=30  nohup sudo bash watchdog-linux.sh > /dev/null 2>&1 &
WD_WATCH='sshd nginx postgres'  nohup sudo bash watchdog-linux.sh > /dev/null 2>&1 &
```

#### `watchdog-pfsense.sh`

Same idea for pfSense. `/bin/sh` only — no bash features. Uses FreeBSD `service -e` + `sockstat -4l`. Watches the daemons that matter: `sshd`, `php-fpm`, `lighttpd` (WebGUI), `unbound`/`dnsmasq` (DNS), `dhcpd`, `ntpd`, `syslogd`, `cron`.

```sh
nohup sh /root/watchdog-pfsense.sh > /dev/null 2>&1 &
tail -f /root/.ecitadel/watchdog-thebox.log
kill $(cat /root/.ecitadel/watchdog-thebox.pid)
```

Outputs `/root/.ecitadel/watchdog-thebox-{baseline.txt,.log,.pid}`. Same event vocabulary as Linux + `TICK-DAEMON` (a watched daemon's process count changed).

> **Why no Windows watchdog?** Cabal is the keystone box and gets a heavier operator touch — manual `Get-Service` / `Get-ScheduledTask` cadence plus Event Log filtering covers it. If you want a polling loop on Windows, schedule `windows-triage.ps1` via Task Scheduler at a fixed interval and `diff` the resulting `.log` files.

### harden/

The only directory in `scripts/` that **modifies system state**. Windows-only. Every script in here:

- Supports `-DryRun` (prints what would change, makes no edits)
- Reads the current value before writing — if it's already at target, the write is **skipped** and counted as no-op
- Verifies the new value after writing
- Logs every change to `~/.ecitadel/harden-<name>-<host>-<ts>.log` (binary fingerprint of "what I changed at T+X" for the inject judge)
- Is **idempotent** — re-running the same script ten times produces the same end-state and the same skip counts

**What's intentionally NOT in `harden/`:**

| CP-style script does | We skip because |
|---|---|
| Imports a generic `.wfw` Windows Firewall config | Blocks scored ports (53/88/389/445/636/3389) on Cabal |
| Disables RDP | RDP is a scored service on Cabal |
| Mass-resets every user password to one shared value | Scoring engine has cached creds — would zero every AD-backed service for at least one round |
| Disables SMB or downgrades to file-only mode | SMB is a scored service on Cabal |
| Disables Administrator unconditionally | Risks locking the team out of the DC; we gate this behind `-DisableBuiltInAdmin` AND a verified replacement admin |
| Wipes scheduled tasks / services indiscriminately | AD replication, DNS server service, scoring-side dependencies live here |

If you need any of the above, do it by hand against the box's actual scored-service list — not from a script.

#### `harden-registry-windows.ps1`

Applies a curated set of registry hardenings safe for the round.

```powershell
.\harden-registry-windows.ps1 -DryRun     # show what would change
.\harden-registry-windows.ps1             # apply
```

Touches (only these — each verified after write):

- **LSA**: `NoLMHash=1`, `LimitBlankPasswordUse=1`, `RestrictAnonymous=1`, `RestrictAnonymousSAM=1`, `EveryoneIncludesAnonymous=0`
- **WDigest**: `UseLogonCredential=0` (kills the Mimikatz plaintext-credential cache path)
- **SMB server**: `RequireSecuritySignature=1`, `EnableSecuritySignature=1`, `SMB1=0` (SMBv2/v3 stays on — AD + scored SMB still work)
- **SMB client**: matching signing requirements
- **DNSClient**: `EnableMulticast=0` (disable LLMNR — AD DNS via the DC still resolves)
- **Explorer**: `NoDriveTypeAutoRun=0xFF`, `NoAutorun=1`
- **UAC**: `EnableLUA=1`, `ConsentPromptBehaviorAdmin=2`
- **PowerShell logging**: `ScriptBlockLogging=1`, `ModuleLogging=1` (free forensic visibility)

Some changes (LLMNR, WDigest, SMB signing) need a logoff or reboot to fully take effect. Re-run `check-policy-windows.ps1` after.

#### `harden-accounts-windows.ps1`

Account + password-policy hardening.

```powershell
.\harden-accounts-windows.ps1 -DryRun
.\harden-accounts-windows.ps1                                    # apply defaults
.\harden-accounts-windows.ps1 -MinLen 16 -LockoutThr 10
.\harden-accounts-windows.ps1 -DisableBuiltInAdmin -NewAdminUser 'op17'
```

Sections, in order:

1. **Guest** — disable RID-501 on both local SAM and AD. Always safe.
2. **Local password policy** via `net accounts` — `MinPasswordLength`, `MaxPasswordAge`, `MinPasswordAge`, `PasswordHistoryLength`, `LockoutThreshold`, `LockoutDuration`, `LockoutWindow`. Defaults: `MinLen=14`, `MaxAge=60d`, `MinAge=1d`, `History=24`, `LockoutThr=5`, `LockoutDur=15min`. Lockout duration is deliberately short (15 min) so a single bad-cred probe doesn't park legit auth.
3. **AD default domain password policy** via `Set-ADDefaultDomainPasswordPolicy` (only on a DC). Same values, plus `ComplexityEnabled=$true` and `ReversibleEncryptionEnabled=$false`.
4. **PasswordNeverExpires sweep** — clears the flag on every enabled local + AD user. Skips: `krbtgt`, the currently-running user, gMSA / computer accounts (`*$`), RID 500 Administrator, and anything you pass in `-Preserve @('svc_app', 'svc_db')`.
5. **Built-in Administrator (RID 500)** — disable only when `-DisableBuiltInAdmin` AND `-NewAdminUser <name>` are both set. The script verifies `<name>` is actually in the local Administrators group before disabling RID 500. If the check fails, RID 500 is left alone.

Tunable parameters: `-MinLen`, `-MaxAgeDays`, `-MinAgeDays`, `-History`, `-LockoutThr`, `-LockoutDur`, `-Preserve`.

---

## Getting scripts onto each box

T+0 access is via web-VMRC console — no `scp` until WireGuard is up. Three options:

1. **Curl from a private Gist** — paste each script into a Gist before comp; on the box: `curl -O https://gist.../linux-triage.sh && bash linux-triage.sh`. Lab boxes have internet.
2. **Paste via console** — open the script locally, copy, paste into `cat > linux-triage.sh <<'EOF' … EOF`. Slow but always works.
3. **SCP after VPN** — once WireGuard is up, `scp -r scripts/` from your laptop to each box. Fastest if you prepared the tree locally.

The bootstrap scripts assume the whole `scripts/` tree lives next to them (they copy from `../triage/` and `../watchdog/`). If you paste just `bootstrap-debian.sh` alone, the install of tools still runs — staging just gets skipped with a "no staging done" note.

---

## Capturing & comparing console output

The structured logs from `*-triage.sh` are the high-leverage observability layer. But you'll also run a lot of ad-hoc commands during the round (`Get-ADUser`, `ss -tlnp`, `pfctl -sr`, `journalctl -xe`). Capture those too — running the same command twice and comparing is the single highest-leverage observability move in the round.

### Capture every interactive shell

```bash
# Linux box:
script -f ~/shell-$(hostname)-$(date -u +%Y%m%d-%H%M%SZ).log
# ... do work, then `exit` to stop recording.
```

```powershell
# Windows (Cabal):
Start-Transcript -Path "$env:USERPROFILE\shell-$env:COMPUTERNAME-$(Get-Date -UFormat %Y%m%d-%H%M%SZ).log"
# ... do work, then:
Stop-Transcript
```

```sh
# pfSense (BusyBox /bin/sh — no `script(1)`):
TS=$(date -u +%Y%m%d-%H%M%SZ)
sh -i 2>&1 | tee /root/shell-thebox-$TS.log
# ... do work, then `exit`.
```

### One-shot command capture

```bash
# Single command:
ss -tlnp | tee ~/ss-tlnp-$(date -u +%Y%m%d-%H%M%SZ).txt

# Periodic (every 30s for 5 min) — scroll later to spot when a port appeared:
for i in $(seq 1 10); do
    echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    ss -tlnp
    sleep 30
done | tee ~/ss-watch-$(date -u +%Y%m%d-%H%M%SZ).log
```

### Comparing two snapshots

For triage logs, use `compare-triage.sh` (above). For ad-hoc diffs:

```bash
# Same box, two runs:
diff -u triage-blacklist-20260531-130000Z.log triage-blacklist-20260531-140000Z.log
diff -u --suppress-common-lines triage-*.log

# Across boxes (same OS), parity check on one section:
diff -u <(grep -A50 '=== USERS ===' triage-blacklist-*.log | tail -1) \
        <(grep -A50 '=== USERS ===' triage-concierge-*.log | tail -1)
```

```powershell
# Windows:
Compare-Object (Get-Content prev.log) (Get-Content this.log) |
    Format-Table SideIndicator,InputObject -AutoSize
```

### One-section compare

```bash
awk '/=== NETWORK ===/{f=1} /=== SERVICES ===/{f=0} f' triage-blacklist-*.log
```

Pipe that into `diff` for a focused compare.

### Diff timing notes

- **Stable inputs first.** `systemctl list-units` produces different order across runs unless you `sort` it. The triage scripts already sort; if you write your own, do too.
- **PIDs change every run.** Strip them with `sed 's/pid=[0-9]*//g'` before diff — or just use `compare-triage.sh`.
- **Timestamps in the data drift.** If a section has wall-clock time in each line (e.g., `last -n 50`), filter or pin a baseline; otherwise every diff is 100% noisy.

### Capture cadence during the round

| When | What | Why |
|---|---|---|
| Pre-comp (laptop) | `check-services.sh` smoke test | Catch bash bugs on dry land, not under pressure |
| T+0 to T+5 per box | `bootstrap-{debian,fedora}.sh` | FOSS toolkit, workdir, staged scripts |
| T+5 to T+10 per box | `first-run-checks.sh` | 60s sanity — is the box even usable? |
| T+10 to T+25 per box | `linux-triage.sh` / `windows-triage.ps1` / `pfsense-triage.sh` / `external-check.sh` | Ground-truth baseline |
| T+25 onward | `watchdog-linux.sh` / `watchdog-pfsense.sh` backgrounded | Continuous deltas, zero operator effort |
| Every 5-10 min | `check-network.sh` / `check-services.sh` | Cheap scoreboard / connectivity verify |
| After baseline + after any user/policy inject | `check-policy-linux.sh` / `check-policy-windows.ps1` | Prove the policy actually took — flags weak min-length, never-expiring passwords, enabled Administrator / Guest |
| Once, after baseline, with `-DryRun` first | `harden/harden-registry-windows.ps1` + `harden-accounts-windows.ps1` | Apply the safe Cabal hardenings (LM hash off, WDigest off, SMBv1 off, Guest disabled, password policy applied). Re-run `check-policy-windows.ps1` after to confirm |
| Every ~60 min | Re-run `*-triage.sh` → `compare-triage.sh` | Catches what watchdog doesn't (file changes, sudoers, SUID) |
| Every console session | `script` / `Start-Transcript` | Post-mortem + IR evidence — "what did I do?" |
| Before filing any IR | Fresh triage + `external-check.sh` | IR needs current evidence, not 2h-old state |
| Before any revert | Final triage of the box | The revert wipes state; you'll want a record |
| On suspect PID | `ir-capture.sh <PID>` **then** `kill -9` | Evidence before containment, always |

### Don't trust your memory

When the scoreboard flips red, the first instinct is "I think I changed something on Concierge five minutes ago." That instinct is wrong half the time. With `script` transcripts + watchdog deltas + periodic triage snapshots, you don't have to remember — you can `grep` the last 15 minutes.

---

## Getting reports off each box

```bash
# from your laptop, once VPN is up:
scp 'user@172.27.17.102:~/.ecitadel/triage-concierge-*.log' ~/notes/
scp -r 'user@172.27.17.102:~/.ecitadel/evidence/' ~/notes/
```

For Cabal, use SMB or `winrm` if you've set them up, otherwise paste from the console.

---

## Reading the output

Each report is a transcript. Section banners (`=== SECTION ===`) let you jump around with your editor's outline view.

### Triage checklist (skim the report, in order)

1. **Header** — confirm the box is who you think it is (hostname, OS, uptime).
2. **USERS / LOCAL USERS** — flag any account you don't recognize. Cross-check against the password-change inject spec. Did anything get created in the last 7 days?
3. **NETWORK / TCP listeners** — anything bound on `0.0.0.0` other than the scored service? Anything on a port you don't expect (4444, 8080, 31337, anything > 50000)?
4. **SCHEDULED TASKS / cron / systemd timers** — any task with a weird `Author`, `RunAs SYSTEM`, weird filename, or recently created?
5. **PERSISTENCE VECTORS** — any `authorized_keys` you don't recognize? Any Run-key entries? Any WMI event subscriptions (almost never legitimate)?
6. **RECENT FILE CHANGES** — anything in `/etc`, `/var/www`, `C:\ProgramData` modified after the round started?
7. **WEB ARTIFACTS** (Linux) — webshell-pattern hits or oversized PHP files. Treat anything in `*/uploads/*` as guilty until proven innocent.
8. **DEFENDER / SELinux / firewall** — confirm posture: Defender real-time on, SELinux `Enforcing`, firewall has the scored ports.
9. **External summary** — green or red for each scored service. If green externally but red on the scoreboard, the issue is likely auth (AD).

If a section flags something, capture the line, run `ir-capture.sh <PID>` if it's a live process, hash any binary involved, and feed it into `templates/ir-report.md`.

---

## Safety notes

- These scripts never modify config, kill processes, change passwords, or block IPs. Everything is `cat` / `ls` / `Get-*` / `pfctl -s*` / `dig` / `ping`.
- They dump root-readable data into the operator's home dir. **Don't** leave the `.log` on the box if you've extracted it — `shred -u` (Linux) or `Remove-Item -Force` (Windows) after pulling.
- `external-check.sh` and `check-services.sh` are the only scripts that touch a remote system — and only your own team's external /24 (or your internal range if `BASE=` is set). Do not modify either to point elsewhere; that's a DQ-able offence.
- `ir-capture.sh` reads `/proc/<pid>/exe` and copies the binary. On hardened kernels with `kernel.yama.ptrace_scope=2`, the copy will fail silently for processes you don't own — use `sudo`.
