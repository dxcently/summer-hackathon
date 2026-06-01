# eCitadel Season IV — Competition Plan

> RR Intel network. 6h + 5min grace. CCS 20% + Injects 35% + Services 35% + Orange 10%.
> Red team is a penalty category (subtractive). Assume pre-planted malware on every box.

## Scoring math (know what to prioritize)

| Category | Weight | Posture |
|---|---|---|
| Scored services (7) | 35% | **Never let them go red.** Non-SSH = 3 pts/check, SSH = 1 pt/check. SLA penalty = 3× point value after 5 consecutive misses. |
| Injects | 35% | **PDF only. Always submit something.** Even "no time, ack" is worth more than silence (missing = penalty). |
| CCS (find-and-fix) | 20% | Heavy malware + forensics + auditing + hardening. MP3/MP5 hunts are NOT scored. |
| Orange team tickets | 10% | Triage portal tickets every ~10 min. Auto-grader after the fact. |
| Red team | penalty | File IR reports to claw points back. |

**Implication:** services + injects = 70% of score. Lose one for the sake of the other and you're done.

---

## Pre-competition prep (do BEFORE the round)

- [ ] Watch last year's debrief video end-to-end — flagged by orgs as the single most valuable prep
- [ ] Pull last season's challenges from `dxcently.com` (or the orgs' "source" site) — same shape as this year
- [ ] Install Google Chrome (Firefox has portal bugs)
- [ ] Install WireGuard client — VPN config only downloadable after start, but the client should be ready
- [ ] Pre-stage a PDF export workflow: Pandoc + LaTeX, or Google Docs → PDF, or Obsidian → PDF
- [ ] Decide team roles before start:
  - **Lead / Triage** — owns inject portal + scoreboard, dispatches work
  - **Linux box owner** — Blacklist (Debian DB) + Concierge (Fedora web)
  - **Windows owner** — Cabal (DC + AD + DNS)
  - **Network owner** — pfSense + IR reports
  - **Inject writer** — turns evidence into PDFs (this person does NOT touch boxes)
- [ ] Pre-write inject PDF templates (`templates/inject-response.md`)
- [ ] Pre-write IR report template (`templates/ir-report.md`)
- [ ] Build a personal cheatsheet of hardening commands per OS (`docs/02-hardening.md`)
- [ ] Stage repo scripts on a USB / shared volume so they're reachable from each VM:
  - `scripts/triage/check-policy-linux.sh`, `scripts/triage/check-policy-windows.ps1` — read-only policy audits
  - `scripts/harden/harden-linux.sh`, `scripts/harden/harden-accounts-windows.ps1`, `scripts/harden/harden-registry-windows.ps1` — apply-with-backup hardenings
  - `scripts/triage/linux-triage.sh`, `scripts/triage/windows-triage.ps1`, `scripts/triage/pfsense-triage.sh` — baseline snapshots
- [ ] Dry-run every hardening script (`--dry-run` / `-DryRun`) against a practice box before round day
- [ ] Practice round: run the full plan end-to-end, find what breaks

---

## T-5min — Grace period checklist (you cannot touch VMs yet)

- [ ] Open portal in Chrome, log in via Discord
- [ ] Read the README under Announcements **first**
- [ ] Confirm all 4 VMs appear in the VMs tab (Debian / Fedora / Windows / pfSense)
- [ ] Wait for scoreboard to go all-green — confirms orgs delivered a working baseline
- [ ] Download WireGuard config from portal, bring tunnel up locally
- [ ] Identify which inject portal section holds the **password-change format** — read it now, do not change passwords yet
- [ ] Skim any injects already present
- [ ] Confirm team roles, pick a shared note doc

---

## T+0 to T+30min — Triage phase (do not break anything yet)

**Goal:** map the boxes, snapshot reality, stop bleeding. No password changes yet.

- [ ] Each box owner: log in via web console, capture baseline
  - Run the canned snapshot: `linux-triage.sh` / `windows-triage.ps1` / `pfsense-triage.sh` (writes a tarball to `~/.ecitadel/`)
  - users (`/etc/passwd`, `net user`, `Get-LocalUser`, `Get-ADUser -Filter *`)
  - listening ports (`ss -tlnp`, `netstat -ano`)
  - running services (`systemctl list-units --type=service`, `Get-Service`)
  - scheduled tasks / cron (`crontab -l`, `ls /etc/cron.*`, `schtasks /query`, `Get-ScheduledTask`)
  - SUID binaries (`find / -perm -4000 -type f 2>/dev/null`)
  - sudoers (`cat /etc/sudoers`, `ls /etc/sudoers.d/`)
  - SSH authorized_keys for every user
  - Windows: `Get-LocalUser`, AD admins (`Get-ADGroupMember "Domain Admins"`), persistence (`Autoruns`, registry Run keys)
- [ ] Run the read-only policy audits (no writes, safe pre-password-change):
  - Linux: `sudo bash scripts/triage/check-policy-linux.sh`
  - Windows: `powershell.exe -ExecutionPolicy Bypass -File scripts\triage\check-policy-windows.ps1`
  - Skim `[FAIL]` / `[warn]` lines — they map directly to the per-OS checklists below
- [ ] Identify the **7 scored services**. Confirm each works from inside before touching anything.
  - SSH on which box(es)?
  - HTTP/HTTPS on Concierge — which app? Test login with the AD account.
  - DNS on Cabal (AD-integrated) — `dig @172.21.0.103 rrintel.internal`
- [ ] Identify AD bind / service accounts the scoring engine + orange team use. **Do not delete these.**
- [ ] Verify orange-team operations portal is reachable and tickets visible
- [ ] Take baseline notes — write to shared doc, not just screen
- [ ] Check first inject(s), assign to inject writer

---

## T+30 to T+90min — Stop active compromise

**Goal:** kick out red team without breaking services. Document everything for IR reports.

- [ ] Kill obviously malicious processes, but capture artifacts first (`/proc/PID/exe`, copy binary, hash it, note CLI args)
- [ ] Disable unknown user accounts (don't delete — break-glass)
- [ ] Remove rogue SSH keys from authorized_keys (back them up first as evidence)
- [ ] Disable unknown cron / scheduled tasks (move to `.disabled` rather than delete)
- [ ] Windows: clear malicious Run keys, kill unknown services, check for golden-ticket / Kerberoast artifacts
- [ ] **Password-change inject (when ready):** ONE submission, exact format, all accounts in one shot
  - Includes: every service account scoring engine uses + every orange-team user
  - **Do not spam.** Rate-limited ~1 change / 30 min. Disqualifying if abused.
- [ ] After password change: verify all 7 services still green within one scoring round (2-3 min + 2-3 min report)
- [ ] First IR report for the obvious malware you cleaned (claw back red team penalties)

---

## T+90min to T+5h — Sustain + harden + injects

**Goal:** keep scoreboard green, knock out injects in PDF.

**Rolling loops (every team member):**
- Scoreboard check every 5 min
- Inject portal check every 10 min
- Orange team ticket check every 10 min

**Per-box hardening — pick high-value items only, see `docs/02-hardening.md` and the per-OS checklists below:**
- [ ] Debian (Blacklist / DB) — see **Linux checklist**
  - First: `sudo bash scripts/harden/harden-linux.sh --dry-run` then apply (login.defs, pwquality, sshd, sysctl, cron.allow, shadow perms — auto-backed up to `~/.ecitadel/backups/`)
  - DB users: drop guest/anonymous, rotate `root`/admin, restrict bind to LAN
  - UFW or nftables: deny inbound except scored ports + LAN admin (script intentionally does NOT touch firewall — confirm scored ports first)
  - `apt update && apt upgrade -y` only if you can roll back via revert if something breaks
- [ ] Fedora (Concierge / Web) — see **Linux checklist**
  - Same hardening script applies (`harden-linux.sh` is distro-agnostic)
  - Web app: audit admin users, look for upload backdoors, check `wp-content/uploads`-style paths
  - PHP / Node / whatever: kill unknown listeners, remove webshells
  - SELinux: leave enforcing
  - Audit `/var/www` for backdoors (look for `eval(`, `base64_decode(`, recent mtimes)
- [ ] Windows (Cabal / DC) — see **Windows checklist**
  - First: `.\scripts\harden\harden-registry-windows.ps1 -DryRun` then apply (LSA, WDigest, SMB signing, LLMNR off, UAC, PowerShell logging)
  - Then: `.\scripts\harden\harden-accounts-windows.ps1 -DryRun` then apply (password policy, lockout, disable Guest, unset PasswordNeverExpires — does NOT reset existing passwords)
  - Domain Admins: kick anyone you didn't expect, but **NOT** the scoring/orange service accounts
  - DNS: confirm scoring engine queries still resolve after hardening
  - Defender: enable, run quick scan
- [ ] pfSense (thebox)
  - WAN allow-list: scored ports only inbound
  - **Block individual red-team IPs you've observed in IR — never block /24s** (you'll block the scoring engine)
  - Log everything for IR evidence

**Inject loop (writer + box owner):**
1. Inject writer reads requirement, confirms acceptance criteria
2. Box owner executes, captures screenshots / config diffs
3. Writer drops evidence into `templates/inject-response.md`, exports PDF
4. Submit PDF on portal **before due time**
5. Even if abandoning: submit a 1-line "team did not have capacity" PDF

**Orange team loop:**
- Read ticket, reply on portal in plain English
- Don't fix the underlying issue from the ticket alone — verify on the box too

---

## T+5h to T+6h — Wrap phase

- [ ] Stop touching boxes 30 min before end. Last hour is fragile.
- [ ] Submit ack-PDFs for any open injects you can't finish
- [ ] File final IR reports for any red team activity in last hour
- [ ] Confirm services all green going into the final scoreboard freeze
- [ ] Save logs locally (you'll lose access at T+6h)

---

## Linux checklist (Blacklist / Concierge)

Cross-reference with `scripts/triage/check-policy-linux.sh` output. Items marked **FAIL** in the script must be fixed; **warn** items are judgement calls based on scored services.

**Accounts / passwords (`/etc/login.defs`, `/etc/security/pwquality.conf`)**
- [ ] `PASS_MIN_LEN >= 14` (script applies; FAIL threshold = 6)
- [ ] `PASS_MAX_DAYS <= 60` (warn if > 90)
- [ ] `PASS_MIN_DAYS >= 1` (zero allows immediate re-change after forced reset)
- [ ] `PASS_WARN_AGE >= 7`
- [ ] pwquality: `minlen`, `dcredit`, `ucredit`, `lcredit`, `ocredit`, `enforce_for_root`, `dictcheck=1`
- [ ] PAM stack wires in `pam_pwquality` + password `remember=` (history)
- [ ] No empty password hashes in `/etc/shadow` (FAIL)
- [ ] Exactly one UID 0 account (root) — script flags duplicates as FAIL
- [ ] System accounts (UID < 1000) locked (`!` or `*` in shadow)
- [ ] No `chage -l` shows "never expires" on a human account
- [ ] No `NOPASSWD:` in sudoers / sudoers.d/ except service accounts you can justify

**SSH (`/etc/ssh/sshd_config`)**
- [ ] `PermitRootLogin no`
- [ ] `PermitEmptyPasswords no`
- [ ] `MaxAuthTries 4`, `LoginGraceTime 30`
- [ ] `ClientAliveInterval 300`, `ClientAliveCountMax 2`
- [ ] `X11Forwarding no`, `UsePAM yes`
- [ ] **DO NOT** flip `PasswordAuthentication no` mid-round unless you've confirmed the scoring engine uses keys
- [ ] Every user's `~/.ssh/authorized_keys` reviewed — back up before pruning rogue keys

**Kernel / network (`/etc/sysctl.d/99-ecitadel-harden.conf`)**
- [ ] `net.ipv4.tcp_syncookies = 1`
- [ ] `net.ipv4.conf.all.rp_filter = 1`
- [ ] `net.ipv4.conf.all.accept_redirects = 0`, `send_redirects = 0`
- [ ] `net.ipv4.conf.all.accept_source_route = 0`
- [ ] `kernel.kptr_restrict = 2`, `kernel.dmesg_restrict = 1`
- [ ] `kernel.yama.ptrace_scope = 1`

**Persistence / scheduled execution**
- [ ] `/etc/cron.allow` and `/etc/at.allow` exist and contain `root` only
- [ ] `crontab -l` for every user reviewed; unknowns moved to `.disabled` (don't delete — evidence)
- [ ] `ls -la /etc/cron.{hourly,daily,weekly,monthly}/` and `/etc/cron.d/` reviewed
- [ ] `systemctl list-timers --all` reviewed
- [ ] `systemctl list-unit-files --state=enabled` — disable anything unfamiliar that isn't scored

**Filesystem / forensics**
- [ ] `/etc/shadow` and `/etc/gshadow` are `640 root:shadow` (or `000`)
- [ ] SUID list saved as baseline (`find / -perm -4000 -type f 2>/dev/null > ~/.ecitadel/suid-baseline.txt`)
- [ ] `find /tmp /var/tmp /dev/shm -type f -mtime -1` — recent drops in world-writable dirs
- [ ] `find / -name '.*' -mtime -1 2>/dev/null` — hidden recent files
- [ ] `ls -la /root /home/*` for stray scripts / authorized_keys / .bashrc backdoors
- [ ] No suspicious listeners (`ss -tlnp` matches only scored services + ssh)

**Service / web (Concierge specifically)**
- [ ] Web admin users audited; rotate the credential per password-change inject
- [ ] `/var/www` scanned for `eval(`, `base64_decode(`, `assert(`, `gzinflate(`, recent mtimes
- [ ] Upload directories don't execute (`Options -ExecCGI`, no `.php` in uploads)
- [ ] SELinux `enforcing` (don't drop to permissive)

---

## Windows checklist (Cabal — DC + AD + DNS)

Cross-reference with `scripts/triage/check-policy-windows.ps1` output. The hardening scripts write registry + AD policy; this checklist covers what they touch plus the manual items.

**Password / lockout policy (`net accounts` + `Get-ADDefaultDomainPasswordPolicy`)**
- [ ] `MinimumPasswordLength >= 14` (script applies; FAIL < 6)
- [ ] `MaximumPasswordAge <= 60` days
- [ ] `MinimumPasswordAge >= 1` day (kills immediate-cycling history bypass)
- [ ] `PasswordHistoryLength >= 24`
- [ ] `LockoutThreshold` between 1 and 10 (FAIL if 0 — never locks)
- [ ] `LockoutDuration <= 15 min` (don't park scoring engine for an hour)
- [ ] AD: `ComplexityEnabled = True`, `ReversibleEncryptionEnabled = False`
- [ ] `krbtgt` password age < 180 days (warn beyond)

**Local accounts (`Get-LocalUser`)**
- [ ] RID 500 Administrator: disabled OR renamed + password rotated (only disable when a replacement admin exists — script gates this)
- [ ] RID 501 Guest: **disabled** (FAIL if enabled — script disables)
- [ ] RID 503 DefaultAccount: disabled
- [ ] No account has `PasswordRequired = False` (FAIL)
- [ ] No enabled account has `PasswordNeverExpires = True` (except documented service accounts in `-Preserve`)

**AD accounts (`Get-ADUser -Filter *`)**
- [ ] Built-in Administrator / Guest reviewed
- [ ] `Domain Admins` membership matches expected list — kick unknowns, **keep** scoring + orange service accounts
- [ ] `PasswordNotRequired -eq $true` → none (FAIL)
- [ ] Stale accounts (`LastLogonDate` > 90 days, still enabled) → disable

**LSA / authentication registry (`harden-registry-windows.ps1`)**
- [ ] `HKLM\System\CurrentControlSet\Control\Lsa\NoLMHash = 1`
- [ ] `LimitBlankPasswordUse = 1`
- [ ] `RestrictAnonymous = 1`, `RestrictAnonymousSAM = 1`
- [ ] `EveryoneIncludesAnonymous = 0`
- [ ] `...\SecurityProviders\WDigest\UseLogonCredential = 0` (kills Mimikatz plaintext)

**SMB / network**
- [ ] SMB signing required (`RequireSecuritySignature = 1` server + client)
- [ ] SMBv1 disabled (`SMB1 = 0`)
- [ ] LLMNR disabled (`EnableMulticast = 0` under DNSClient policy)
- [ ] NetBIOS over TCP/IP disabled per adapter (manual)
- [ ] **Do NOT** disable SMB/RDP/DNS — all scored on Cabal

**UAC / auto-run**
- [ ] `EnableLUA = 1`, `ConsentPromptBehaviorAdmin = 2`
- [ ] `NoDriveTypeAutoRun = 0xFF`, `NoAutorun = 1`

**Persistence**
- [ ] Run keys: `HKLM\Software\Microsoft\Windows\CurrentVersion\Run` + `RunOnce` (+ Wow6432Node + HKCU equivalents)
- [ ] `Get-ScheduledTask | Where State -ne 'Disabled'` — review unknown tasks; export XML before disabling (evidence)
- [ ] `Get-Service | Where {$_.StartType -eq 'Automatic'}` — review unknowns
- [ ] `Autoruns.exe -nobanner -accepteula -a *` snapshot saved
- [ ] WMI event subscriptions: `Get-WmiObject -Namespace root\subscription -Class __FilterToConsumerBinding`

**Logging / Defender**
- [ ] PowerShell ScriptBlock + Module logging enabled (`harden-registry-windows.ps1` sets these)
- [ ] Windows Defender enabled, signatures updated, quick scan run
- [ ] Event log sizes raised (Security/System/Application/PowerShell-Operational)
- [ ] `wevtutil el` reviewed for unfamiliar channels

**DC-specific**
- [ ] After every change: `dig @<dc-ip> rrintel.internal` (or `Resolve-DnsName`) still resolves
- [ ] `repadmin /showrepl` clean (if multi-DC)
- [ ] DNS zones reviewed for rogue records (esp. wildcard / `*` A records)

---

## Revert decision tree

Reverts: 4 free per team. Lose all CCS pts + all box changes. Keep service/SLA pts.

```
Service red AND you can't diagnose in 5 min?
├── Is the dependency upstream (DC down → web down)? → Fix the dependency, NOT this box
├── Did red team destroy the OS? → Revert
└── Did YOU misconfigure? → Try to fix from console; revert only if stuck >10 min

A box getting hammered by red team repeatedly?
└── Revert is a reset, not a fix. They'll re-pop. Harden BEFORE reverting back.
```

**Never revert a box whose service is already red because of an upstream dependency.** It'll come back red.

---

## Hard "do not do" list

- Do **NOT** scan .1 or .2 on your subnet (upstream gateway / pfSense)
- Do **NOT** scan other teams, red team, or out-of-scope hosts → DQ
- Do **NOT** block subnets (only individual IPs)
- Do **NOT** submit injects as non-PDF (they will not look at it — zero points)
- Do **NOT** spam password-change submissions → DQ
- Do **NOT** delete the scoring-engine service accounts in AD
- AI agent: if you use one, fence it to your VMs. Out-of-scope scanning by your AI = DQ on you.
- Do **NOT** use real credentials anywhere on the VMs — assume exfil

---

## Review (post-comp)

Fill in after the round:

- What scored well: …
- What broke and why: …
- Time wasted on: …
- Add lessons to `tasks/lessons.md`
