# scripts/

First-run triage scripts. All read-only. Run these immediately after T+0 on each box (and from your laptop) to capture a known-state baseline before you change anything. Re-run later in the round and `diff` the two reports to spot deltas.

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
# → ~/triage-<hostname>-<utc-ts>.log
```

Captures: users (`/etc/passwd`, `/etc/shadow`, sudoers), network (interfaces, listeners, routes), services + cron + systemd timers, persistence vectors (SUID/SGID, all `authorized_keys`, profile.d, systemd unit files), recently modified files in `/etc`, `/var/www`, `/tmp`, processes, web artifacts (webshell candidates, oversized PHP), DB listeners, SSSD/AD-join state, SELinux/AppArmor, firewall rules, sshd_config, package install log, recent journal errors, recent logins.

### `windows-triage.ps1`

Read-only triage for **Cabal (Windows Server 2022 / DC + DNS for `rrintel.internal`)**.

```powershell
# On Cabal, in PowerShell as Administrator:
powershell.exe -ExecutionPolicy Bypass -File windows-triage.ps1
# → %USERPROFILE%\triage-<computer>-<utc-ts>.log
```

Captures: local users + groups, all AD users (with whenCreated, last logon, password set), AD users created in the last 7 days, Domain Admins / Enterprise Admins / Schema Admins / Administrators / Account Operators membership, AD computers, accounts with non-expiring passwords, accounts with SPNs (Kerberoast surface), running services, non-Microsoft auto-start services, non-Microsoft scheduled tasks, tasks running as SYSTEM, HKLM/HKCU Run keys + RunOnce, Win32_StartupCommand, WMI event filters + consumers + bindings, network (IP config, listeners, established connections), firewall profile state, DNS server zones + `rrintel.internal` records, SMB shares + sessions + config (SMBv1 status), interactive sessions, Defender status + preferences + threat history, recent Security events (4624 logon, 4625 failed logon, 4720 user-created, 4732/4756 group add, 7045 service install), recently modified files in `C:\ProgramData`, `C:\Users\Public`, `C:\Windows\Temp`, audit policy.

### `pfsense-triage.sh`

Read-only triage for **pfSense (thebox)**. Uses pfSense's `/bin/sh` — no bash features. Uses `pfctl`, `sockstat`, and direct reads of `/cf/conf/config.xml`.

```sh
# In the pfSense console menu, choose 8 (Shell), then:
sh /root/pfsense-triage.sh
# → /root/triage-thebox-<utc-ts>.log
```

Captures: interfaces (ifconfig, stats), pf rules + NAT rules + state table summary + first 100 states, routing table, local TCP/UDP listeners (sockstat), installed packages + running services + daemons, admin users from `config.xml`, NAT 1:1 + inbound rdr rules, recent webGUI/SSH auth events, last 100 firewall log lines, last 100 system log lines.

### `external-check.sh`

Probes scored services **from outside pfSense**, the way the scoring engine does. Run from your VPN'd operator laptop. Probes ONLY your team's external /24 — never another team, never red team.

```bash
# On your VPN'd operator laptop:
bash external-check.sh 17        # replace 17 with your team number
# → ./external-check-<utc-ts>.log
```

Checks: ICMP reachability for all three hosts, DNS from Cabal (A/SOA/NS for `rrintel.internal`, `_ldap._tcp` SRV, `_kerberos._tcp` SRV, reverse), SSH on .101/.102/.103, HTTP+HTTPS on Concierge (status, headers, TLS cert), DB ports on Blacklist (5432/3306/1433), AD/LDAP ports on Cabal (389/636/88/3389/445/53). Ends with a one-table pass/fail summary.

> **Important:** `external-check.sh` returning `HTTPS OK (200)` is *necessary but not sufficient*. The scoring engine actually logs in and exercises functionality — a 200 from a placeholder/error page still scores zero. After this script reports green, hit the app in your browser and do one real login action.

## Getting scripts onto each box

The boxes are accessed via web-VMRC console at T+0. You can't `scp` straight away. Easiest paths:

1. **Curl from a public Gist** — paste the script into a private Gist before comp; on the box: `curl -O https://gist.../linux-triage.sh && bash linux-triage.sh`. Lab boxes have internet.
2. **Paste via console** — open the script locally, copy, paste into a `cat > linux-triage.sh <<'EOF' … EOF` on the box. Slow but always works.
3. **SCP after VPN is up** — once you have the WireGuard tunnel, scp from your laptop to each box. Fastest if you already prepared the scripts on your laptop.

## Getting reports off each box

After running, you want the `.log` file on your laptop / shared notes so all owners can grep it.

```bash
# from your laptop, once VPN is up:
scp user@172.27.17.102:~/triage-concierge-*.log ~/notes/
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
