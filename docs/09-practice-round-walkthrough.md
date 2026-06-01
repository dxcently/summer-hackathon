# 09 — Practice round walkthrough

> A methodology guide. No answers. Different systems than the actual competition (Linux Mint 21, Alma Linux 9, Windows Server 2016, pfSense — vs the real comp's Debian 13 / Fedora 43 / Win Server 2022). But the *shape* of the work — the categories of findings, the order you approach them, the penalties that bite you — is the same. Treat the practice round as the lowest-difficulty version of the real thing, not as a separate game.
>
> The practice answer keys exist. Don't read them first. The whole point is to develop the muscle of *finding* the problems. Looking up answers after the fact, with a list of things you missed, is fine. Looking them up beforehand teaches you nothing.

## What the practice round actually is

You get three VMs + a firewall. Theme is "crewmate" (Among Us-flavored). Your account is `cyan`. There's a README on the desktop / home directory of each box that tells you:

- The authorized users
- The required software
- The critical services (SSH, HTTP, FTP, DNS, RDP, SQL — varies per box)

The README is your **source of truth**. If a user isn't in it, that user shouldn't exist. If software isn't in it (and isn't OS/service infrastructure), that software shouldn't be installed. If a service is listed as critical, you do not touch it except to harden it.

There's also a CCS agent on each box silently scoring. You don't see the rubric. You see your point total move up or down. Positive moves = you fixed something legitimate. Negative moves = you broke something you weren't supposed to.

**Key differences from the real comp:**

| | Practice | Real comp |
|---|---|---|
| Red team | None | Active, pre-planted malware |
| Orange team | None | 10% of score |
| Inject difficulty | Easier, fewer | Full pace |
| CCS on firewall | No | Yes |
| Check interval | Every 5 min | Every 2–3 min |
| Time limit | None (2 days) | 6 hours |
| Failure mode | Mild | Cascading red across services |

The practice round won't punch you in the mouth. The real one will. Use the practice round to build the *order of operations* in your head so the real one doesn't.

## Mindset: don't touch anything for the first 10 minutes

Newcomers immediately start fixing things. That is the single biggest mistake. Read first. Change second.

1. Read the README on every box. All of it.
2. Read the forensics questions on every box. All of them. **Do not modify the box yet.**
3. Open a notes doc. Write down: authorized users, required software, critical services, anything the README explicitly says not to do.
4. Now you can start.

Why this matters: many forensics questions ask "what was the X" — you can't answer that after you've changed X. Many findings are about deltas from the README — you can't audit a delta if you haven't read the spec.

## Order of operations (the loop you'll repeat per box)

```
1. Forensics questions (READ-ONLY, answer them, save the answers)
2. README audit — what should be there?
3. User accounts — who shouldn't be there?
4. Privileged group membership — who has too much access?
5. Passwords + policy
6. Services + processes
7. Firewall + network config
8. Updates / patches
9. Prohibited software + media
10. Backdoors + IoCs
11. Service-specific hardening (SSH, RDP, FTP, DNS, web)
12. Final verification — every critical service still works externally
```

Don't bounce around. Finish a category before moving to the next. The reason: every category roughly maps to one type of CCS check, and you want to be able to tell from the score whether your action helped, hurt, or did nothing. Bouncing makes the signal noisy.

## Practice injects (in parallel with the per-box work)

The practice round also fires at least one inject through the team portal. Injects are independent from CCS — they have their own point pool, their own deadline, and their own grading. Check the portal periodically (every 10 min is fine for the practice round) and dispatch any new inject to a teammate.

Practice injects don't require PDF submissions the way the real comp does — the system just checks whether you actually did the thing on the box. But the *workflow* you build here is the same one you'll use under PDF pressure during the real comp, so practice it intentionally.

### Worked example: "New User Inject"

```
Title:    New User Inject
Tasking:  The crewmates just hired a new employee, and you need
          to create a new user account for them with a secure
          password.
Phase 1:  Create a new domain user named olive.
Phase 2:  Assign a secure password to the user olive.
Phase 3:  Make sure the user olive is enabled.
```

**Step 1 — Read all three phases before you click anything.**

The phases are checkpoints the grader will verify. If you finish Phase 1 but skip Phase 3, the inject is wrong, even if the obvious "create the user" step is done. Newcomers do this constantly: they create the account, see it appear in the list, mark themselves done. Then it scores zero because they didn't notice Phase 3 existed.

Write the phases down somewhere visible. Cross them off as you complete them.

**Step 2 — Identify the box.**

"Create a new *domain* user" → this is Active Directory work, not local users. AD lives on the DC. In the practice round that's `polus` (Windows Server 2016). Open the AD Users and Computers MMC there (`Run → dsa.msc`).

If you create the user as a *local* user on `polus` (via `lusrmgr.msc`) instead of a *domain* user, the grader will not see it and the inject fails. Same name. Same password. Wrong place. Zero points. Read the tasking carefully and pick the right tool.

**Step 3 — Phase 1: create the user.**

Navigate to `crewmate.local → Users` in the left pane. Right-click `Users` → New → User. The wizard asks for First/Last name, Full name, User logon name. The literal text the grader checks is the *User logon name*. Spell it exactly as the inject specifies — `olive`, lowercase, no whitespace, no decoration. Don't add a job title, don't add a number, don't make it `Olive` with a capital. The grader does a literal match.

**Step 4 — Phase 2: assign a secure password.**

The wizard's next page asks for a password. "Secure" here means: meets the domain's password policy *and* isn't trivially guessable. Don't use:

- The username (`olive`) — trivially weak
- A short string (under 10 chars) — likely fails policy
- A blank password — fails policy and is the exact thing you're being graded for *not* doing

Pick something reasonable: 12+ characters, mixed case, a digit, a symbol. Write it down somewhere you can retrieve it after the round; you may need to log in as this user for verification. If the domain password policy rejects your choice, AD will tell you on the next click — pick a stronger one.

You'll also see four checkboxes on this screen:

- `User must change password at next logon` — usually checked by default. **Uncheck it** unless the inject specifically asks otherwise; leaving it checked means the user is in a "must change before they can do anything" state, which can trip grading scripts that try to bind as them.
- `User cannot change password` — leave unchecked.
- `Password never expires` — leave unchecked (max-age policy will pick it up later).
- `Account is disabled` — **leave unchecked.** This is Phase 3.

**Step 5 — Phase 3: confirm the user is enabled.**

After clicking through the wizard, find `olive` back in the Users container. Look at the icon:

- A normal user icon = enabled
- A user icon with a small down-arrow overlay = disabled

If you see the down-arrow, right-click → "Enable Account". Verify the icon updates.

To verify programmatically (good habit — the grader uses programmatic checks):

```powershell
Get-ADUser olive -Properties Enabled,PasswordLastSet | Select Name,Enabled,PasswordLastSet
```

`Enabled` should report `True`. `PasswordLastSet` should be the time you just created the account, not `1/1/1601` (which means the password was never actually set).

**Step 6 — Verify before declaring done.**

```powershell
# does the account exist with the exact logon name?
Get-ADUser olive

# is it in the Users container (i.e., a domain user) and not somewhere weird?
Get-ADUser olive -Properties DistinguishedName | Select DistinguishedName

# is it enabled?
(Get-ADUser olive).Enabled

# can you actually authenticate?
# (optional, but a great sanity check — try to RDP in as olive on a non-DC box)
```

If all four come back the way you expect: inject done. Mark it off in your notes.

### Inject workflow lessons (apply to every inject, practice or real)

- **Phases are not suggestions.** Each phase is independently scored. Miss one, lose the points for one even if the others land.
- **Match the literal text.** Names, paths, values — if the inject says `olive`, use `olive`. Not `Olive`, not `olive1`, not `olive@crewmate.local`.
- **Verify after each phase, not just at the end.** A single PowerShell line confirming the state is cheap and stops the "I thought I clicked the right thing" failure mode.
- **Time-box hard.** If a practice inject would take you 45 minutes, the real-comp equivalent takes 45 minutes and you have 4–6 other injects in flight. Build the speed muscle now.

The real comp inject workflow adds two layers on top of this: a PDF response per inject (see `docs/03-injects.md` for the worked example) and a writer/owner role split. The technical execution is the same.

## 1. Forensics questions

There will be one or more files named something like `Forensics Question 1` on the Desktop (Windows / Mint) or in your home directory (Alma). Open every one and read it before you touch anything else on the box.

Each question is testing a basic admin/forensics skill: list a DB table, find an MP3 path, find the first line of a banner, identify a CNAME, find the first process in `ps -ef`, etc.

How to approach:

- **Don't change the thing the question is about until you've answered it.** If the question references a database, don't drop the database. If it references a file, don't delete the file. Several questions test something that another step would have you remove — the order matters.
- **The answer goes somewhere specific.** On Linux, into the file itself or wherever the question tells you. On Windows, the same. Read the question carefully — they say where.
- **Tools you already know how to use.** `ps`, `head`, `mysql -u <user> -p`, DNS Manager, `dnsmgmt.msc`, `ftp <ip>`, `locate '*.ext'`, `find / -name`. If you don't know one of these, look it up *now*, not during the comp.

If you're stuck on a forensics question, *skip it temporarily*, do other work, come back. Don't sit on a 10-point question while a 50-point category goes untouched.

## 2. README audit

Write down, from each box's README, the answers to:

- Which users are authorized? (Both admins and non-admin.)
- What software is *required*? (You'll lose points if you remove it.)
- What services are *critical*? (You'll lose points if you stop them.)
- Any specific policy claims? (e.g., "no media files", "passwords must be strong", "RDP must be enabled from any public IP")

Everything you do for the rest of the round flows from this list. Treat the README as a written contract.

## 3. User accounts

You have the authorized-user list from the README. Now find the actual list on each box.

**Linux** — Look at `/etc/passwd`. Compare names against the README. Pay attention to UID ranges — system accounts (UID < 1000) are usually legit; human accounts (UID ≥ 1000) are who you're auditing.

```bash
awk -F: '($3 >= 1000) {print $1}' /etc/passwd
```

**Windows** — On the DC, this is *Active Directory*, not local users.

```
Run → dsa.msc   (Active Directory Users and Computers)
```

Local user manager (`lusrmgr.msc`) is mostly empty on a domain controller — AD owns the user database. On non-DC Windows boxes (not relevant to this practice round but relevant later), local users live in `lusrmgr.msc`.

**Removal vs disabling.** In a real round with a red team you'd *disable* first, in case the account turns out to be legit. In practice round there's no red team and the README is authoritative, so removal is fine. But pick a method you're comfortable with — `userdel -r` on Linux removes home dir, `userdel` doesn't; deletion on Windows leaves traces in event log either way.

## 4. Privileged group membership

Even users that are *allowed to exist* should not necessarily be admins.

**Linux** — Look at `/etc/sudoers`, `/etc/sudoers.d/*`, and group membership (`getent group sudo wheel adm`).

**Windows** — Two layers, both critical:

```
dsa.msc → crewmate.local → Builtin → Administrators (local administrators)
dsa.msc → crewmate.local → Users    → Domain Admins (domain-wide admins)
```

Plus `Enterprise Admins` and `Schema Admins` if present. The README tells you who's an authorized administrator. Membership of these groups should be *exactly* that set, plus the built-in `Administrator` account.

Don't blindly delete the built-in Administrator account. Don't empty Domain Admins entirely — you'll lock yourself out of administering the domain. Remove specific users from groups, don't nuke the groups.

## 5. Passwords and password policy

Two things to check.

**Specific weak passwords.** If a user's password is literally their username, or is in the README as plaintext, change it. Don't go ham resetting every password — that breaks the auto-login user (`cyan`) and may break service accounts you don't see yet.

**Password policy.**

- *Minimum length* — make it ≥ 10. Linux: `/etc/pam.d/common-password` or `/etc/security/pwquality.conf` depending on distro. Windows: Group Policy → Account Policies → Password Policy.
- *Maximum age* — Linux: `/etc/login.defs` (`PASS_MAX_DAYS`). Windows: GPO same path.
- *Minimum age* — set to non-zero so users can't cycle through 24 passwords in a minute to bypass history.
- *Lockout threshold* — set between 5 and 50 (Windows: `Account Lockout Policy`). Lower than 5 = users lock themselves out by typo. Zero = no lockout = brute force unrestricted.
- *Password history* — make them remember the last N.

For practice round, focus on minimum length first — it's reliably scored across all three boxes.

## 6. Services and processes

A running service you don't need is an attack surface you didn't have to give up.

**Inventory current state first.**

```bash
# Linux
systemctl list-units --type=service --state=active --no-pager
ss -tlnp        # what's listening
ps -ef          # what's running

# Windows
Run → services.msc
Run → netstat -abonp TCP    # what's listening + which process
```

Then ask, for each one: "Is this a critical service per the README? Is it OS infrastructure I shouldn't touch? Is this something I never asked for?"

Examples of things newcomers leave running that shouldn't be: mail-related daemons (postfix, sendmail, dovecot) on a box that isn't a mail server; print spooler on a server with no printer; debug services bound to localhost. If you don't know what a service is, *look it up before you stop it*.

**Stop AND disable** — stopping alone means it restarts on reboot.

```bash
sudo systemctl stop <name>
sudo systemctl disable <name>
```

**The big do-not-stop list** (each one of these earns a penalty if killed):

- SSH on any Linux box (it's a critical service)
- The DB engine on whatever box hosts the SQL/WordPress data
- Apache / httpd on the web box
- DNS on the DC
- RDP on Windows
- WordPress, PHP, and all their files
- FTP on whatever box hosts the FTP critical service
- SYSVOL and NETLOGON shares on the DC (these support AD)
- SMB client service v2/v3 (AD depends on it)

If you're not sure, leave it running. CCS deducts points if you turn off a critical service. There's no CCS bonus for leaving a non-critical service running, but there's also no harm.

## 7. Firewall and network

**Linux firewall** — Mint uses `ufw`; Alma uses `firewalld`. Both should be **enabled** and survive reboot.

```bash
# Mint
sudo ufw status
sudo ufw enable

# Alma
sudo systemctl status firewalld
sudo systemctl enable --now firewalld
```

If you enable the firewall and the scored SSH or HTTP check goes red, your firewall is dropping the scoring engine. Add an explicit allow rule for whatever port is scored before re-enabling.

**Windows firewall** — `wf.msc` → Properties → all three profiles → On.

**Kernel network params (Linux)** — `/etc/sysctl.conf` (or files in `/etc/sysctl.d/`). The one most commonly scored: IPv4 forwarding should be `0` on a server that isn't a router. After editing, run `sysctl -p` to reload.

```
net.ipv4.ip_forward=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
```

(Don't paste a giant `sysctl` hardening list blindly — anything that interferes with the scored services costs you.)

## 8. Updates and patches

Updating software fixes known CVEs. CCS rewards specific upgraded packages (the answer keys list which ones each box scores).

```bash
# Mint / Debian
sudo apt update && sudo apt upgrade -y

# Alma / RHEL family
sudo dnf upgrade -y
```

**Watch for:**

- *Repository config first.* On Mint, the security-updates repo may be commented out — uncomment it before `apt update`. On Alma, you may want `dnf-automatic` enabled.
- *Major version migrations.* The README on the SQL box says **do not upgrade MariaDB past 10.6**. Updates within 10.6 are fine. Read the README; don't blindly `upgrade -y` past version pins.
- *Windows OS updates aren't scored.* But the *applications* on Windows are. Chrome especially.

After updating, restart anything affected. SSH especially — `sshd` won't pick up new code without a restart, and if a CVE-patched version is needed, the running process matters, not the installed binary.

## 9. Prohibited software and media files

The README says no unauthorized media. The README implies no hacking tools. CCS will reward you for removing both.

**Find media files (Linux):**

```bash
sudo updatedb
locate '*.mp3' '*.wav' '*.mp4' '*.avi' '*.flac'
# or
find / -type f \( -name '*.mp3' -o -name '*.mp4' \) 2>/dev/null
```

A user's home `Music/` or `Videos/` directory is the most common location. Don't delete the directory; delete the files. Don't delete `/usr/share/sounds/` — those are system sound files.

**Find prohibited software (Linux):**

```bash
# Mint
dpkg -l | less          # full list
# Alma
rpm -qa | less

# Sort by install time on Alma
rpm -qa --last | head -30
```

Common practice-round flags: network attack tools (Nmap, Wireshark), memory editors, game launchers / multiplayer game clients. Anything you wouldn't expect on a *production server*.

```bash
# Mint
sudo apt remove <package>
# Alma
sudo dnf remove <package>
```

**Find prohibited software (Windows):**

- `Settings → Apps → Apps & features` — sorted by install date, scroll for things that don't belong
- Desktop icons that aren't shortcuts (no shortcut overlay = it's the executable, deleting the icon deletes the program)
- Tools commonly flagged: PUPs (CCleaner-style), hacking tools, third-party browsers that aren't the required one

Delete it, then re-scan for any leftover scheduled tasks or autorun entries the installer left behind.

**Do not remove:**

- The required software listed in the README (Chrome on Windows, Chromium on Mint, lynx on Alma in this practice round). Removing it is a penalty.
- Service-supporting infrastructure (PHP if WordPress is required, etc.).

## 10. Backdoors and IoCs

This is the most fun category and the one most worth slowing down on.

**The hunt has three layers:** network → process → persistence.

### Network layer

Anything listening on a port you didn't expect is suspicious. "Expected" = the scored services + standard infrastructure (DNS, AD, etc.).

```bash
# Linux
sudo ss -tlnp
sudo lsof -i -n -P

# Windows
netstat -abonp TCP
netstat -abonp UDP
```

Read the **process column**. A listener whose process name doesn't match the port's role is a tell. A listener on a port like 1337, 4444, 31337 (anything that screams "I picked this myself") is a tell. A listener whose process is a weird filename in `C:\Users\Public` or `/tmp` is a tell.

### Process layer

Once you have a suspicious PID, look at the binary:

```bash
# Linux
ls -la /proc/<pid>/exe         # readlink to the binary
sha256sum /proc/<pid>/exe       # hash before killing
ps -p <pid> -o pid,ppid,user,cmd
```

```powershell
# Windows
Get-Process -Id <pid> | Select Path, Company, FileVersion
Get-FileHash <path-from-above>
```

**On Windows, the Sysinternals tools (Process Explorer, Autoruns, TCPView) make this dramatically easier.** If they're available on the practice box, use them. They show you the same info as Task Manager but with much better column control + parent process tree + signed-vs-unsigned + autorun entries in one place.

### Persistence layer

A killed process means nothing if the attacker has a way to restart it. Before you delete the binary, check:

- **Linux**: `/etc/cron.*`, `/etc/cron.d/`, `/var/spool/cron/`, `systemctl list-timers --all`, every user's `~/.ssh/authorized_keys`, `/etc/systemd/system/*`, `/etc/rc.local`, `/etc/profile.d/`
- **Windows**: HKLM and HKCU `\Software\Microsoft\Windows\CurrentVersion\Run` and `RunOnce`, scheduled tasks (especially in `\` root path, not `\Microsoft\...`), WMI event subscriptions, services with weird `ImagePath`

For the practice round, expect *exactly one* obvious backdoor on the Windows box and possibly a webshell-style implant on the Linux web box (look in the web root for files that don't belong). The order of operations:

```
1. Snapshot evidence (hash, take note of the path, the port, the parent PID)
2. Kill the process
3. Disable / remove the persistence (the autorun or scheduled task)
4. Delete the binary
```

If you delete the binary first, the persistence may re-fetch it from somewhere. If you only kill the process, it comes back at next reboot.

## 11. File shares (Windows)

Open `fsmgmt.msc` → Shares. You should see:

- `ADMIN$`, `C$`, `IPC$` — Windows administrative shares. **Leave them.** Microsoft does not recommend disabling these and CCS doesn't reward it.
- `SYSVOL`, `NETLOGON` — Active Directory shares. **Leave them.** Disabling either is a penalty.
- Anything else — audit. The README doesn't say SMB shares are needed for the practice critical services. An ad-hoc `C` drive share, or a share of `C:\Users\Public`, is almost certainly something you should stop sharing.

To stop sharing: right click → Stop Sharing.

Don't disable SMB v2/v3 as a "hardening" step on the DC. AD depends on SMB. Disabling SMBv1 is correct; disabling v2/v3 will silently break authentication on every domain member.

## 12. Service-specific hardening

Once the box is generally clean, harden each critical service. Keep changes *minimal* — one config knob per pass, restart the service, verify the external check still passes.

### SSH

`/etc/ssh/sshd_config`. Common scored items across the practice boxes:

```
PermitRootLogin no
PermitEmptyPasswords no
```

After editing:

```bash
sudo sshd -t              # validate config — DO THIS BEFORE RESTARTING
sudo systemctl restart sshd
```

Don't set `PasswordAuthentication no` on the practice round — you'll lock yourself out of the box (no key-based auth is set up).

### FTP (Alma)

`/etc/vsftpd/vsftpd.conf`. Look for `anonymous_enable=YES` — switch to `NO`. Restart `vsftpd`.

### RDP (Windows)

- *Must remain enabled* — it's a critical service. Don't disable it.
- *Enable Network Level Authentication.* `Run → systempropertiesremote.exe` → "Allow connections only from computers running Remote Desktop with Network Level Authentication (recommended)".
- *Verify after change.* Try to RDP in from outside. If you can't, you broke it; revert.

### DNS (Windows)

`Run → dnsmgmt.msc` → Forward Lookup Zones → your domain. Look at every record:

- `A` records that point to IPs you don't recognize
- `CNAME` records that route to suspicious aliases (a CNAME pointing your `wordpress.crewmate.local` at the attacker's box is a clean phishing vector)
- New records with weird names

The forensics question for the Windows box hinges on this view. Read it carefully before you delete anything — and remember that legitimate CNAMEs *do* exist in normal DNS. Don't nuke records you don't understand.

### HTTP / WordPress (Alma)

The practice round's web box is WordPress on Apache. Things to look at:

- Admin users in the WordPress DB (`wp_users` table)
- File modification times in `/var/www/html/` and subdirectories — anything modified after the snapshot timestamp is suspect
- Files in `wp-content/uploads/` that aren't images — especially `.php` files (webshell red flag)

Don't move WordPress out of its install location. Don't delete PHP. The README says these are required.

## 13. Sensitive files

The Windows box has a plaintext credential file sitting in a user's Documents folder. The general lesson: **search every authorized user's home directory for files containing credentials.**

```bash
# Linux
grep -RiE 'password|passwd|secret|api_key|token' /home /root 2>/dev/null
find /home /root -name '*.txt' -o -name '*.csv' -exec ls -la {} \;
```

```powershell
# Windows
Get-ChildItem C:\Users -Recurse -Include *.txt,*.csv,*.xls* -Force -ErrorAction SilentlyContinue |
    Select-String -Pattern 'password|passwd|admin|p@ssw' |
    Select Path,Line -First 50
```

If you find credentials in a file: **delete the file** (the practice scenario considers this a leak even if the password is also stored properly elsewhere). Don't try to "redact" — just delete.

## 14. Browser configuration

Whatever browser the README lists as required, harden its settings:

- Block pop-ups + redirects
- Block intrusive/misleading ads
- Make sure it's *at the latest version*

For Chrome / Chromium, settings live at `chrome://settings/content/` URLs:

- `chrome://settings/content/popups`
- `chrome://settings/content/ads`

On Windows, you can enforce these for all users via Chrome's Group Policy ADMX templates, but per-user settings via the UI are fine for the practice round.

## 15. The "do not do these" list

Each of these is a known CCS penalty. Memorize them.

| Don't | Why |
|---|---|
| Stop SSH on any Linux box | SSH is a scored critical service |
| Stop FTP on the box where FTP is scored | Scored critical service |
| Stop the SQL service | Scored critical service |
| Stop Apache / httpd on the web box | Scored critical service |
| Stop DNS on the DC | Scored critical service |
| Disable RDP on the Windows box | Scored critical service |
| Remove the required browser | Required software per README |
| Remove `lynx` (Alma) / Chromium (Mint) | Required software per README |
| Remove PHP | WordPress needs it |
| Move WordPress out of its install path | Critical service file |
| Disable SMB client v2/v3 | Breaks AD |
| Disable SYSVOL or NETLOGON shares | Breaks AD |
| Set account lockout threshold below 5 | Lets attackers DoS your users by locking them out |
| Change the `cyan` user's password (autologin) | Documented in README, breaks autologin |
| Change a VM's IP | Documented in README, breaks the scoring NAT mapping |
| Take new snapshots | You can't anyway, but don't try |

The pattern: **the README is authoritative.** If it says something is required, treat it as untouchable infrastructure regardless of how dumb the configuration looks.

## 16. How to verify a fix without waiting for CCS

CCS updates in real time but the score-delta isn't always obvious. Verify the change actually applied:

- **For a removed user**: `id <user>` → should error
- **For a stopped service**: `systemctl is-active <svc>` → `inactive`; `ss -tlnp | grep <port>` → empty
- **For a removed package**: `which <binary>` → empty; `dpkg -l | grep <pkg>` / `rpm -qa | grep <pkg>` → empty
- **For a config knob**: re-read the file, find the line, confirm value
- **For SSH/sshd changes**: `sudo sshd -t` before restart, then `ssh -v <localhost>` after to confirm

Don't trust your edit. Trust the verification.

## 17. After the practice round

When you're done — or out of time — read the answer keys. Match them against your work:

- **What you got** — note the category. This is something you're now reliable at.
- **What you missed entirely** — note the category and the exact step. Add it to your team's pre-comp checklist.
- **What you broke** — this is more valuable than what you got right. The penalty categories are *exactly* the things red team will weaponize against you in the real comp.
- **What took too long** — identify the time sink. Was it a UI you didn't know? A command you had to look up? Fix that before comp day.

The forensics questions, the user audit, and the firewall enable are essentially free points if you know the workflow. If you didn't get all of those, drill them until the muscle is there.

## 18. Translating to the real comp

Same shape, harder:

| Practice category | Real-comp equivalent |
|---|---|
| README check | The org-issued briefing + portal announcements |
| Authorized users | Password-change inject spec |
| Unauthorized users | Red team accounts + leftover ops portal users |
| Forensics questions | Most early injects |
| Service hardening | Same idea, much higher stakes (orange team logs in via these) |
| Backdoors | Same hunt, but red team is *actively* planting new ones during the round |
| Firewall | pfSense, not local UFW/firewalld; same principles |

The practice round teaches you *what to look for*. The real round adds *speed*, *active opposition*, and *PDF paperwork*. Don't underweight the paperwork — injects are 35% of the real comp's score, vs zero in the practice round.

If the practice round felt comfortable: good. The real one will not. Use the comfort to drill speed and team handoffs — owner → writer → submission — until the round-of-show is reflexive.
