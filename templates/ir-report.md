# Instant Report — <Short Event Description>

**Team:** Team <NN>
**Host:** <blacklist / concierge / cabal / thebox>
**Detected at:** <YYYY-MM-DD HH:MM UTC> (local: <HH:MM>)
**Reported at:** <YYYY-MM-DD HH:MM UTC>
**Reporter:** <name>
**Status:** [Open | Contained | Closed]

---

## Indicator(s)

| Type | Value |
|---|---|
| Source IP | <a.b.c.d> |
| Process | <name + PID> |
| File path | <absolute path> |
| Hash (SHA-256) | <hash> |
| User account | <username> |
| Log source | <journal / Event Log / web log path> |

## Narrative

<2-4 sentences: what happened, when you noticed, how you noticed.>

## Evidence

### Log excerpt

```text
<timestamped log lines — include timestamps>
```

### Command output / screenshot reference

```text
<ps / lsof / netstat / Get-Process output, or "see attached PNG">
```

### File / registry artifact

```text
<file listing, hash, or registry path>
```

## Impact assessment

- **Scored services affected:** <list, or "none observed">
- **Data potentially accessed/exfilled:** <describe, or "unknown">
- **Persistence achieved by attacker?:** <yes/no + how>

## Containment actions

1. <What you did first — be exact: command, file, timestamp>
2. <Next action>
3. <Next>

## Mitigation / hardening applied

- <Block rule in pfSense (rule name / IP)>
- <Account disabled (username)>
- <File quarantined / removed (path)>
- <Cron / scheduled task disabled>
- <Other>

## Residual risk

<What still might be open. What you'd watch for.>

## Verification

<How you confirmed containment was effective — re-scan output, log silence, service back green, etc.>

---

> Generated for Season IV / RR Intel Task Force. Submitted via portal.
