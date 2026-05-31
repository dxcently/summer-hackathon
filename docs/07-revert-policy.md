# 07 — Revert policy

> 4 free reverts per team. Each revert wipes the box back to the org-issued baseline, loses all CCS points + your work, but keeps service points + SLA history.

## What a revert actually does

- VM rolls back to the **org-issued snapshot** (the original config you were handed)
- VM ends up **powered off** — you must power it back on
- You **lose all CCS points** earned on that box
- You **lose all changes** you made (configs, packages, evidence files)
- **Service points + SLA points are NOT reset** — those live on the scoreboard, not the box
- You **cannot take new snapshots** — only the original is available

## Quota

- **4 reverts total per team, free**
- Either: revert 1 box 4 times, or 4 boxes 1 time each, or any combo summing to ≤4
- 5th+ revert = **penalty** (amount not displayed; calculated post-comp; orgs say "subject to change")
- Penalties are not visible until the debrief

## When revert IS the right call

1. **Red team has rooted the box and you can't trust the OS.** Wiping is faster than chasing.
2. **You bricked the OS yourself** (broken firewall, broken sshd, lost console access).
3. **Boot is broken** (init failure, fs corruption).
4. **Mass file deletion by red team** that you don't have backups for.

## When revert IS NOT the right call

1. **Service red because of upstream dependency** (DC down → web down). Reverting the web box does nothing; DC is still down.
2. **Service red because YOU misconfigured something <5 min ago.** Try to fix from console first.
3. **Red team keeps re-popping the same way.** A revert resets, but they'll re-pop within minutes. Harden the entry vector FIRST, then revert.
4. **You're holding meaningful CCS points on the box.** Compare points-lost vs time-to-fix.

## Decision tree

```
Service is red AND I can't restore it within 10 min?
│
├── Is the failure downstream of another box?
│       Yes → Fix that box, NOT this one
│       No  → continue
│
├── Did I break it with a config change I can identify?
│       Yes → Revert the config (Edit/Ctrl-Z), not the box
│       No  → continue
│
├── Is the OS unbootable / unreachable?
│       Yes → REVERT
│       No  → continue
│
├── Has red team done something I can't undo (deleted DB, encrypted FS)?
│       Yes → REVERT
│       No  → Keep troubleshooting
```

## Pre-revert checklist

- [ ] Confirm root cause is on THIS box (not DC, not pfSense)
- [ ] Count remaining reverts (X of 4 used)
- [ ] Capture artifacts you want to keep (export evidence files via SSH/SMB to another box or your VPN host)
- [ ] Note what hardening you'd done so you can redo it faster
- [ ] Tell the team "reverting <box>"
- [ ] Click revert in portal
- [ ] **Power the VM back on** (revert leaves it off)
- [ ] Re-apply password change submission if AD users were rotated (the org snapshot has the originals)
- [ ] Re-apply your top-3 hardening items immediately
- [ ] Confirm scoreboard recovers within 5-10 min

## After a revert, watch for

- **Red team re-popping fast** — they had pre-plants on the snapshot too. Apply containment in first 5 min.
- **Wrong passwords** — the snapshot is back to factory passwords; orange team + scoring engine still have your submitted passwords cached. Re-submit password change if needed.
- **Dependent services still red** — if the box you reverted was a downstream consumer of a broken upstream, reverting won't help.

## Budgeting reverts

| Reverts left | Posture |
|---|---|
| 4 | Use freely if needed |
| 3-2 | Pause before reverting; confirm root cause |
| 1 | Save for catastrophic failure only |
| 0 | Every revert from here is a penalty — fix in place |
