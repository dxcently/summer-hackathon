# scripts/

First-run triage scripts. All read-only. Run these immediately after T+0 on each box (and from your laptop) to capture a known-state baseline before you change anything. Re-run later in the round and `diff` the two reports to spot deltas.

**All scripts write outputs to a hidden workdir** (`~/.ecitadel/` on Linux/laptop, `/root/.ecitadel/` on pfSense, `%USERPROFILE%\.ecitadel\` on Windows). The dir is created on first run with `chmod 700` so a casual `ls` doesn't expose your evidence to anyone who shoulder-surfs the console. On Windows the folder is also marked Hidden. To inspect outputs: `ls -la ~/.ecitadel/`.

## When to run

- **T+0 to T+15 min** (during the triage phase from `tasks/todo.md`):
  - One Linux owner runs `linux-triage.sh` on **both** Blacklist and Concierge
  - Windows owner runs `windows-triage.ps1` on Cabal
  - Network owner runs `pfsense-triage.sh` on pfSense
  - Triage lead (or anyone) runs `external-check.sh` from their VPN'd laptop
- **Every ~60 min** after that — re-run and `diff` against the previous log to spot new users, new cron jobs, new listening ports, new SUID binaries, etc.
- **Before filing any IR** — re-run on the affected box so the IR has fresh evidence

## The scripts

### `linux-triage.sh`

Read-only triage for **Blacklist (Debian 13)** and **Concierge (Fedora 43)**. Auto-detects distro for firewall (`ufw` vs `firewalld` vs `nftables`) and package manager (`dpkg` vs `rpm`).

```bash
# On the target box, as root:
sudo bash linux-triage.sh
# → ~/.ecitadel/triage-<hostname>-<utc-ts>.log
```

Captures: users (`/etc/passwd`, `/etc/shadow`, sudoers), network (interfaces, listeners, routes), services + cron + systemd timers, persistence vectors (SUID/SGID, all `authorized_keys`, profile.d, systemd unit files), recently modified files in `/etc`, `/var/www`, `/tmp`, processes, web artifacts (webshell candidates, oversized PHP), DB listeners, SSSD/AD-join state, SELinux/AppArmor, firewall rules, sshd_config, package install log, recent journal errors, recent logins.

### `windows-triage.ps1`

Read-only triage for **Cabal (Windows Server 2022 / DC + DNS for `rrintel.internal`)**.

```powershell
# On Cabal, in PowerShell as Administrator:
powershell.exe -ExecutionPolicy Bypass -File windows-triage.ps1
# → %USERPROFILE%\.ecitadel\triage-<computer>-<utc-ts>.log
```

Captures: local users + groups, all AD users (with whenCreated, last logon, password set), AD users created in the last 7 days, Domain Admins / Enterprise Admins / Schema Admins / Administrators / Account Operators membership, AD computers, accounts with non-expiring passwords, accounts with SPNs (Kerberoast surface), running services, non-Microsoft auto-start services, non-Microsoft scheduled tasks, tasks running as SYSTEM, HKLM/HKCU Run keys + RunOnce, Win32_StartupCommand, WMI event filters + consumers + bindings, network (IP config, listeners, established connections), firewall profile state, DNS server zones + `rrintel.internal` records, SMB shares + sessions + config (SMBv1 status), interactive sessions, Defender status + preferences + threat history, recent Security events (4624 logon, 4625 failed logon, 4720 user-created, 4732/4756 group add, 7045 service install), recently modified files in `C:\ProgramData`, `C:\Users\Public`, `C:\Windows\Temp`, audit policy.

### `pfsense-triage.sh`

Read-only triage for **pfSense (thebox)**. Uses pfSense's `/bin/sh` — no bash features. Uses `pfctl`, `sockstat`, and direct reads of `/cf/conf/config.xml`.

```sh
# In the pfSense console menu, choose 8 (Shell), then:
sh /root/pfsense-triage.sh
# → /root/.ecitadel/triage-thebox-<utc-ts>.log
```

Captures: interfaces (ifconfig, stats), pf rules + NAT rules + state table summary + first 100 states, routing table, local TCP/UDP listeners (sockstat), installed packages + running services + daemons, admin users from `config.xml`, NAT 1:1 + inbound rdr rules, recent webGUI/SSH auth events, last 100 firewall log lines, last 100 system log lines.

### `external-check.sh`

Probes scored services **from outside pfSense**, the way the scoring engine does. Run from your VPN'd operator laptop. Probes ONLY your team's external /24 — never another team, never red team.

```bash
# On your VPN'd operator laptop:
bash external-check.sh 17        # replace 17 with your team number
# → ~/.ecitadel/external-check-<utc-ts>.log
```

Checks: ICMP reachability for all three hosts, DNS from Cabal (A/SOA/NS for `rrintel.internal`, `_ldap._tcp` SRV, `_kerberos._tcp` SRV, reverse), SSH on .101/.102/.103, HTTP+HTTPS on Concierge (status, headers, TLS cert), DB ports on Blacklist (5432/3306/1433), AD/LDAP ports on Cabal (389/636/88/3389/445/53). Ends with a one-table pass/fail summary.

> **Important:** `external-check.sh` returning `HTTPS OK (200)` is *necessary but not sufficient*. The scoring engine actually logs in and exercises functionality — a 200 from a placeholder/error page still scores zero. After this script reports green, hit the app in your browser and do one real login action.

### `watchdog-linux.sh`

Observe-only background daemon for **Blacklist + Concierge**. Captures a baseline of running services, listening ports, and per-process counts on first tick. Each subsequent tick (default 60 s) compares against baseline + previous tick and logs only **deltas**. Does not restart anything. Does not kill anything.

```bash
# On the target box, as root, after running linux-triage.sh once:
nohup sudo bash watchdog-linux.sh > /dev/null 2>&1 &

# Tail the event log in another shell:
tail -f ~/.ecitadel/watchdog-$(hostname).log

# Stop it cleanly:
kill $(cat ~/.ecitadel/watchdog-$(hostname).pid)
```

Outputs three files in `~/.ecitadel/`:

- `watchdog-<host>-baseline.txt` — snapshot from first tick (services / ports / proc counts)
- `watchdog-<host>.log` — append-only event log, one line per change
- `watchdog-<host>.pid` — pidfile

Event types you'll see in the log:

| Event | Meaning |
|---|---|
| `START` / `STOP` | Watchdog lifecycle |
| `DRIFT-SVC` / `DRIFT-SVC+` | A service active at baseline is now inactive (or vice versa) |
| `DRIFT-PORT` / `DRIFT-PORT+` | A port listening at baseline is no longer listening (or new) |
| `TICK-SVC-` / `TICK-SVC+` | A service changed state since the *previous* tick (catches flaps) |
| `TICK-PROC` | A watched daemon's process count changed |

Tunables via environment variable:

```bash
WD_INTERVAL=30 nohup sudo bash watchdog-linux.sh > /dev/null 2>&1 &
WD_WATCH='sshd nginx postgres' nohup sudo bash watchdog-linux.sh > /dev/null 2>&1 &
```

### `watchdog-pfsense.sh`

Same idea, but for pfSense. Uses `/bin/sh` and FreeBSD's `service -e` + `sockstat -4l`. Watches the pfSense daemons that matter: `sshd`, `php-fpm`, `lighttpd` (WebGUI), `unbound`/`dnsmasq` (DNS), `dhcpd`, `ntpd`, `syslogd`, `cron`.

```sh
# In the pfSense shell:
nohup sh /root/watchdog-pfsense.sh > /dev/null 2>&1 &

# Tail:
tail -f /root/.ecitadel/watchdog-thebox.log

# Stop:
kill $(cat /root/.ecitadel/watchdog-thebox.pid)
```

Outputs `/root/.ecitadel/watchdog-thebox-baseline.txt`, `/root/.ecitadel/watchdog-thebox.log`, `/root/.ecitadel/watchdog-thebox.pid`. Same event-type vocabulary as the Linux watchdog plus `TICK-DAEMON` (a watched daemon's process count changed).

> **Why no Windows watchdog?** Cabal is the keystone box and gets a heavier operator touch — manual `Get-Service` / `Get-ScheduledTask` cadence plus Event Log filtering covers it. If you want a polling loop on Windows, schedule `windows-triage.ps1` via Task Scheduler at a fixed interval and `diff` the resulting `.log` files.

## Getting scripts onto each box

The boxes are accessed via web-VMRC console at T+0. You can't `scp` straight away. Easiest paths:

1. **Curl from a public Gist** — paste the script into a private Gist before comp; on the box: `curl -O https://gist.../linux-triage.sh && bash linux-triage.sh`. Lab boxes have internet.
2. **Paste via console** — open the script locally, copy, paste into a `cat > linux-triage.sh <<'EOF' … EOF` on the box. Slow but always works.
3. **SCP after VPN is up** — once you have the WireGuard tunnel, scp from your laptop to each box. Fastest if you already prepared the scripts on your laptop.

## Capturing & comparing console output

The triage scripts write structured logs. But you'll also run a lot of ad-hoc commands during the round (`Get-ADUser`, `ss -tlnp`, `pfctl -sr`, `journalctl -xe`). Capture those too — running the same command twice and comparing is the single highest-leverage observability move in the round.

### Capture every interactive shell

Run `script` at the start of every console session. It transcribes everything you type **and** everything you see into a file. Costs nothing, saves you when the scoreboard goes red at T+4h and nobody remembers what they did at T+3h45m.

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

### One-shot command capture (`tee` + timestamps)

For a single command whose output you want to keep:

```bash
ss -tlnp | tee ~/ss-tlnp-$(date -u +%Y%m%d-%H%M%SZ).txt
```

For a command run periodically (e.g. every 30 s for 5 min) so you can scroll through and spot when a port appeared:

```bash
for i in $(seq 1 10); do
    echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
    ss -tlnp
    sleep 30
done | tee ~/ss-watch-$(date -u +%Y%m%d-%H%M%SZ).log
```

### Comparing two snapshots

The triage scripts and watchdog snapshots are designed to be `diff`-friendly — every line is structured, sorted where order doesn't matter, banner-delimited where sections do matter.

```bash
# Two triage runs on the same box, find what changed:
diff -u triage-blacklist-20260531-130000Z.log triage-blacklist-20260531-140000Z.log

# Only the section banners differed? Use --suppress-common-lines:
diff -u --suppress-common-lines triage-*.log

# Across boxes (same OS), sanity-check parity:
diff -u <(grep -A50 '=== USERS ===' triage-blacklist-*.log | tail -1) \
        <(grep -A50 '=== USERS ===' triage-concierge-*.log | tail -1)
```

```powershell
# Windows: diff two triage runs
Compare-Object (Get-Content prev.log) (Get-Content this.log) |
    Format-Table SideIndicator,InputObject -AutoSize
```

### Comparing just one section

If a triage log is 2000 lines and you want to compare just `LISTENING TCP`:

```bash
awk '/=== NETWORK ===/{f=1} /=== SERVICES ===/{f=0} f' triage-blacklist-*.log
```

Pipe that into `diff` for a focused compare.

### Diff timing notes

- **Stable inputs first.** `systemctl list-units` produces different order across runs unless you `sort` it. The triage scripts already sort; if you write your own, do too.
- **PIDs change every run.** Strip them with `sed 's/pid=[0-9]*//g'` before diff.
- **Timestamps in the data drift.** If a section has wall-clock time in each line (e.g., `last -n 50`), filter or pin a baseline; otherwise every diff is 100% noisy.

### Recommended capture cadence during the round

| When | What to capture | Why |
|---|---|---|
| T+0 to T+15 | Full `*-triage.sh` / `windows-triage.ps1` per box | Ground-truth baseline |
| T+15 onward | `watchdog-linux.sh` / `watchdog-pfsense.sh` backgrounded | Continuous deltas without operator effort |
| Every 60 min | Re-run `*-triage.sh` per box | Compare with `diff` against the previous one |
| Every console session | `script` / `Start-Transcript` | "What did I do?" for post-mortem + IR evidence |
| Before filing any IR | A fresh triage + `external-check.sh` | The IR needs current evidence, not 2h-old state |
| Before any revert | Final triage of the box | The revert wipes the state; you'll want a record |

### Don't trust your memory

When the scoreboard flips red, the first instinct is "I think I changed something on Concierge five minutes ago." That instinct is wrong half the time. With `script` transcripts + watchdog deltas, you don't have to remember — you can `grep` the last 15 minutes.

## Getting reports off each box

After running, you want the `.log` file on your laptop / shared notes so all owners can grep it.

```bash
# from your laptop, once VPN is up:
scp 'user@172.27.17.102:~/.ecitadel/triage-concierge-*.log' ~/notes/
```

For Cabal, use SMB or `winrm` if you've set them up, otherwise paste from the console.

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

If a section flags something, capture the line, hash any binary involved, and feed it into `templates/ir-report.md`.

## Safety notes

- These scripts never modify config, kill processes, change passwords, or block IPs. Everything is `cat` / `ls` / `Get-*` / `pfctl -s*`.
- They will dump root-readable data into the operator's home dir. **Don't** leave the `.log` on the box if you've extracted it — `shred -u` (Linux) or `Remove-Item -Force` (Windows) after pulling.
- `external-check.sh` is the only one that touches a remote system — and it touches only your own team's external /24. Do not modify the script to point elsewhere; that's a DQ-able offence.
