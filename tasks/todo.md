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
  - users (`/etc/passwd`, `net user`, `Get-LocalUser`, `Get-ADUser -Filter *`)
  - listening ports (`ss -tlnp`, `netstat -ano`)
  - running services (`systemctl list-units --type=service`, `Get-Service`)
  - scheduled tasks / cron (`crontab -l`, `ls /etc/cron.*`, `schtasks /query`, `Get-ScheduledTask`)
  - SUID binaries (`find / -perm -4000 -type f 2>/dev/null`)
  - sudoers (`cat /etc/sudoers`, `ls /etc/sudoers.d/`)
  - SSH authorized_keys for every user
  - Windows: `Get-LocalUser`, AD admins (`Get-ADGroupMember "Domain Admins"`), persistence (`Autoruns`, registry Run keys)
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

**Per-box hardening — pick high-value items only, see `docs/02-hardening.md`:**
- [ ] Debian (Blacklist / DB)
  - DB users: drop guest/anonymous, rotate `root`/admin, restrict bind to LAN
  - `/etc/ssh/sshd_config`: PermitRootLogin no, PasswordAuthentication per scoring needs
  - UFW or nftables: deny inbound except scored ports + LAN admin
  - `apt update && apt upgrade -y` only if you can roll back via revert if something breaks
- [ ] Fedora (Concierge / Web)
  - Web app: audit admin users, look for upload backdoors, check `wp-content/uploads`-style paths
  - PHP / Node / whatever: kill unknown listeners, remove webshells
  - SELinux: leave enforcing
  - Audit `/var/www` for backdoors (look for `eval(`, `base64_decode(`, recent mtimes)
- [ ] Windows (Cabal / DC)
  - Domain Admins: kick anyone you didn't expect, but **NOT** the scoring/orange service accounts
  - Disable LLMNR/NBT-NS, enable SMB signing
  - LAPS if available
  - DNS: confirm scoring engine queries still resolve
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
