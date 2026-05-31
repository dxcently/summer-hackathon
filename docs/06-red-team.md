# 06 — Red team SOP

> Red team is a **penalty** category. Continued compromise costs points. You can claw points back with **Incident Reports (IRs)**.

## Threat model

- "Rogue blacklisters" — automated + hostile agents
- **Pre-planted** on every box at start
- **Phased timeline** — they don't all fire at T+0. Expect waves throughout the round.
- Capabilities:
  - Delete content
  - Stop / disable services
  - Exfiltrate data
- Live on the same subnet as the scoring engine — you cannot block subnet-wide

## Defensive posture

| Stage | Action |
|---|---|
| T+0 | Assume root-equivalent on every box. Treat all default creds as compromised. |
| Triage | Capture artifacts BEFORE killing. Hash binaries, copy `/proc/PID/exe`, screenshot, log timestamps. |
| Contain | Disable accounts (don't delete), rename cron jobs (`.disabled`), kill processes, rotate keys. |
| Block | Individual IPs only, in pfSense, after confirmed activity. Log the rule. |
| Report | File an IR with the evidence (see below). |

## What counts as a confirmed red-team event (for IR)

- New process or binary you didn't create
- New cron/scheduled task / WMI event subscription
- New user account or sudoers entry
- New SSH key in `authorized_keys`
- Service stopped / disabled by something other than you
- Outbound connection to a non-org IP from your box
- Files deleted or modified on web root / DB / system dirs
- New registry persistence on Windows

Take **timestamped screenshots / log excerpts** for each — those are the body of an IR.

## Instant Report (IR) format

See `templates/ir-report.md`. Submit as a PDF on the portal (same as injects).

Minimum contents:
1. **Team + host + timestamp** (UTC and local)
2. **Indicator** — what you saw (IP, process name, file path, hash, log line)
3. **Evidence** — log snippet, screenshot, command output
4. **Action taken** — what you did to contain it
5. **Impact assessment** — what scoring services or data may have been touched
6. **Mitigation status** — open / contained / closed

## When to file an IR

- As soon as you have actionable evidence (don't wait for "complete" picture)
- For each distinct event, not bundled
- File even if the attack was unsuccessful (caught == evidence)

## What NOT to do

- Do **not** scan red team infrastructure → DQ
- Do **not** "hack back" → DQ
- Do **not** poke at observed red-team source IPs (no nmap, no curl)
- Do **not** block /24 subnets — you'll cut off the scoring engine
- Do **not** disable logs / Defender / SELinux to "hide" from red team — CCS will dock you

## Common pre-plant locations to check first

### Linux
- `/etc/cron.d/`, `/etc/cron.*/`
- `/etc/systemd/system/` — fake services
- `~/.ssh/authorized_keys` on every user
- `/var/spool/cron/`
- `/etc/profile.d/*` — login-time exec
- `/etc/rc.local`
- `/dev/shm/`, `/tmp/`, `/var/tmp/` — staging
- `/var/www/` — webshells

### Windows
- Run / RunOnce registry keys (HKLM + HKCU)
- Scheduled Tasks (especially in non-Microsoft TaskPath)
- WMI event subscriptions (`__EventFilter`, `CommandLineEventConsumer`)
- New services (`Get-Service | Where StartType -eq Automatic`)
- Local admin group membership
- Domain admin group membership
- AD account weirdness (recently created, weird description, SPNs)
- GPO with login script
- `C:\ProgramData\` — recently modified executables
- `C:\Users\Public\` — common staging
- Sysmon/Defender exclusions list (red team disables monitoring)

## Triage flow

```
Spot anomaly
    │
    ▼
Snapshot evidence (timestamp, hash, screenshot)
    │
    ▼
Is service-impacting? ──── Yes ──→ Contain (kill, disable) → log it
    │ No
    ▼
Note in IR worklog
    │
    ▼
After containment: write IR PDF → submit
    │
    ▼
Harden the entry point so it doesn't recur
```

## Logging discipline

- Keep a running `incidents.md` file with timestamps + what you saw + what you did
- Every IR you file should map back to a row in that log
- After the comp, those notes become your debrief

---

## Worked example: catching a webshell on Concierge and filing the IR

> Walk through this once if you've never written an IR before. The example is synthetic but representative — webshells in `/var/www` are the single most common red-team artifact you'll encounter on Concierge.

### Step 1 — Spot the anomaly (1 min)

You're doing the recon block from `docs/02-hardening.md` on Concierge. The webshell hunt finds something:

```bash
grep -RElE 'eval\(|base64_decode\(|system\(|exec\(|shell_exec\(' /var/www
```

Output:

```
/var/www/html/wp-content/uploads/avatar/loader.php
```

A `.php` file in an *uploads* directory is almost never legitimate — uploads should hold images, not code. You also notice it's recent:

```bash
ls -la /var/www/html/wp-content/uploads/avatar/loader.php
```

```
-rw-r--r-- 1 www-data www-data 4218 2026-MM-DD 14:03 loader.php
```

The competition started at 13:00. This file was created at 14:03, an hour into the round. Red team planted it during the round, not in the snapshot. **Confirmed indicator.**

### Step 2 — Snapshot evidence BEFORE killing it (3 min)

> The biggest newcomer mistake is to immediately `rm` the file. If you do, you have no evidence and you can't file the IR. Always copy first.

```bash
# 1. Capture identity of the file (don't change the original)
sha256sum /var/www/html/wp-content/uploads/avatar/loader.php
# → c3e8...7f2a (write this down)

# 2. Copy to evidence dir on the same box
mkdir -p ~/evidence/INJ-IR-003
cp -p /var/www/html/wp-content/uploads/avatar/loader.php \
      ~/evidence/INJ-IR-003/loader.php

# 3. Snapshot context — full file listing + first 40 lines of content
ls -la /var/www/html/wp-content/uploads/avatar/ > ~/evidence/INJ-IR-003/listing.txt
head -n 40 /var/www/html/wp-content/uploads/avatar/loader.php \
    > ~/evidence/INJ-IR-003/first-40-lines.txt

# 4. Look in the web server log for the IP that uploaded + executed it
grep 'loader.php' /var/log/nginx/access.log > ~/evidence/INJ-IR-003/access.log.snippet
```

You see a log line like:

```
198.51.100.42 - - [DD/MMM/2026:14:03:11 +0000] "POST /wp-content/uploads/avatar/loader.php HTTP/1.1" 200 312 "-" "curl/8.5.0"
```

That's your **source IP** (`198.51.100.42`) and the **first execution timestamp**.

### Step 3 — Contain (2 min)

> "Contain" = make it stop. Do not delete yet — disabled and renamed is better than gone, because gone removes evidence chain.

```bash
# Make the file non-executable + non-readable by the web server
chmod 000 /var/www/html/wp-content/uploads/avatar/loader.php

# Rename so PHP-FPM no longer matches it as a script
mv /var/www/html/wp-content/uploads/avatar/loader.php \
   /var/www/html/wp-content/uploads/avatar/loader.php.quarantined

# Confirm no shell process is still running from it
ps auxf | grep -i loader
```

Then add a pfSense block for the source IP (network owner does this — see `docs/01-network.md` for why single IPs only, never /24).

### Step 4 — Verify scored service didn't break (1 min)

```bash
# Web check from outside (your VPN'd laptop)
curl -ks https://172.27.17.102/ -o /dev/null -w '%{http_code}\n'
# Expect: 200 (or whatever the baseline was)

# Log in to the actual web app from the browser
# Hit the login flow, click one real action. Scoring engine does this.
```

If the curl is 200 and the login still works, you contained without breaking anything scored. Wait 5 min, watch the scoreboard. Stays green → done.

### Step 5 — Write the IR PDF (5 min)

> Open `templates/ir-report.md` and fill it in. The writer doesn't need to be the box owner — same separation as injects.

Excerpt of the filled-in template:

```markdown
# Instant Report — Webshell on Concierge

**Team:** Team 17
**Host:** concierge (172.21.0.102 / 172.27.17.102)
**Detected at:** 2026-MM-DD 14:07:30 UTC (local: 09:07)
**Reported at:** 2026-MM-DD 14:18:00 UTC
**Reporter:** @linux-owner
**Status:** Contained

## Indicator(s)

| Type | Value |
|---|---|
| Source IP | 198.51.100.42 |
| File path | /var/www/html/wp-content/uploads/avatar/loader.php |
| Hash (SHA-256) | c3e8...7f2a |
| Process | none active at detection time |
| Log source | /var/log/nginx/access.log |

## Narrative

At 14:07 during the standard webshell sweep on Concierge, a PHP
file was found in the WordPress avatar uploads directory. The
file was created at 14:03 (post-snapshot, mid-round), contains
base64_decode + eval, and the access log shows a POST from
198.51.100.42 at the same timestamp. We assess this as a
red-team-planted webshell.

## Evidence

### Log excerpt
198.51.100.42 - - [DD/MMM/2026:14:03:11 +0000] "POST
/wp-content/uploads/avatar/loader.php HTTP/1.1" 200 312
"-" "curl/8.5.0"

### File metadata
-rw-r--r-- 1 www-data www-data 4218 2026-MM-DD 14:03 loader.php
sha256: c3e8...7f2a
First 40 lines: see first-40-lines.txt (PHP eval(base64_decode(...)))

## Impact assessment

- Scored services affected: none observed. Web app login
  still passing at time of IR.
- Data potentially accessed: unknown. The shell ran as
  www-data; uploads dir + DB env file are readable as www-data.
- Persistence: none planted via this shell (sole file;
  no cron / no new user / no SSH key added).

## Containment actions

1. 14:09 — chmod 000 on the file (prevents further exec).
2. 14:10 — Renamed to .quarantined.
3. 14:11 — Added pfSense block on 198.51.100.42 inbound to WAN
   (rule name: ir003-block-198.51.100.42).
4. 14:13 — Verified web app login + scoring URL still pass
   externally.

## Mitigation / hardening applied

- pfSense WAN block on 198.51.100.42 (logged)
- Quarantined webshell (preserved for evidence chain)
- Reviewed remaining /wp-content/uploads/ for other .php
  files → none found

## Residual risk

- Source IP may rotate (red team + scoring engine share subnet,
  cannot block subnet). Will continue monitoring access.log
  for repeat POST attempts in /uploads/.
- WordPress upload-MIME filter likely misconfigured to allow
  .php — followup hardening tracked.

## Verification

- Web check curl -ks https://172.27.17.102/ → 200
- Scoreboard for Concierge HTTP service: green through 14:30
- No further connections from 198.51.100.42 in access.log after
  pfSense block applied
```

### Step 6 — Export to PDF + submit (2 min)

Same workflow as inject submission:

```bash
pandoc INJ-IR-003.md --pdf-engine=xelatex -o INJ-IR-003-webshell-concierge.pdf
```

Submit via portal → IR / Instant Reports tab. Confirm submitted.

### Step 7 — Followup hardening (later — don't block on it)

After the round stabilizes, the linux owner does the actual fix that prevents a repeat:

- Configure nginx / php-fpm to **not** execute `.php` inside `/wp-content/uploads/`
- Tighten WordPress upload MIME filter
- Audit other `uploads/` directories on the box

This is a *separate* later effort. The IR submission is independent — file it as soon as you have evidence + containment, even if the followup hardening is still queued.

### Total time: ~14 minutes

The IR is the high-leverage artifact. A clean IR PDF can claw back a meaningful chunk of red-team penalty. **A perfect technical response with no IR filed earns zero penalty recovery.** Always write the IR.
