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
