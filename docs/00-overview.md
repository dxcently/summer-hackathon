# 00 — Overview

> **New to blue-team competitions?** Read `docs/00a-newcomer-primer.md` first — it frames the whole round before you dive into the scoring math here. Then `docs/08-glossary.md` if any of the acronyms below are unfamiliar (CCS, AD, SLA, inject, etc.).

## Scenario

You are an FBI Joint Task Force read in on Notorious Fixer's criminal intelligence and trading network, now operating under federal control as **RR Intel** (domain `rrintel.internal`). Your job: keep RR Intel's systems online and secure so the network can keep producing intelligence.

The RR Intel Marketplace + Operations Portal must stay running. **Assume rogue operatives are already inside.** Pre-planted malware is on every box.

Run is **virtual**. Resources are limited — don't expect anything heavyweight.

## Scoring breakdown (sums to 100% + penalty)

| Category | Weight | What it measures |
|---|---|---|
| Scored services | 35% | 7 services (SSH, HTTP, DNS) polled externally every 2-3 min by an org-run scoring engine |
| Injects | 35% | Business-memo tasks from the task force. **PDF-only submissions, response required for every inject.** |
| CCS (find-and-fix) | 20% | Live agent on each box scoring forensics, malware removal, auditing, hardening |
| Orange team | 10% | Automated users hitting the operations portal submitting tickets. Replies graded manually post-comp. |
| Red team | penalty | Subtractive. IR reports can claw points back. |

### Service scoring

- Non-SSH up + functional = **3 pts/check**
- SSH up = **1 pt/check**
- Down (or content/functionality broken) = **0 pts**
- **SLA violation:** 5 consecutive misses = penalty equal to 3× point value (i.e. -15 non-SSH / -5 SSH). Non-overlapping; one good check resets the counter.
- Each service has its own SLA counter.

### Service-check semantics

- External polling — services must work from the outside (172.27.X.X), not just LAN
- Web checks verify **login + functionality**, not just an HTTP 200. Static HTML won't earn points.
- Almost all checks use **Active Directory auth against `rrintel.internal`**. If AD goes down → cascading service failures.
- Scoring engine **reuses + changes IPs** and **lives on the same subnet as red team IPs**. Do NOT block subnets.

### CCS scoring

- CCS agent runs on each VM, gives live feedback
- Categories: **forensics, malware removal, auditing, hardening**
- Heavy malware focus. Not random file hunts (no MP3/MP5 points).
- Practice round CCS is broader / demo-only — not reflective of comp difficulty
- pfSense has CCS during comp but **not** during practice round

### Inject scoring

- Delivered on rolling basis via the **Injects tab** of the portal
- Each has start, due, reject time. Late = 0.
- **PDF-only** — anything else won't even be opened
- **Always submit something** — a 1-line "team had no capacity" PDF beats silence (silence is penalized)
- Some injects due immediately, some at end of comp

### Orange team

- Automated users submit tickets via the operations portal
- They use **passwords you submitted via password-change inject**
- If they can't log in (portal broken / wrong password) → lose points
- If you don't reply to their tickets in a reasonable time → lose points
- If you break the portal so much that automation breaks → lose points
- Graded manually after the comp

### Red team

- Rogue blacklisters. Automated + hostile. Pre-planted + phased timeline.
- Can: delete content, stop/disable services, exfil data
- Penalty category — sustained compromise costs points
- **File IR (instant) reports** for caught activity to recover penalty points

## Hard rules

| | |
|---|---|
| Scan .1 / .2 on your subnet | **DO NOT** — those are upstream gateway and pfSense |
| Scan other teams / red team / out-of-scope | **DO NOT** → DQ |
| Block /24 subnets | **DO NOT** — you'll block the scoring engine |
| Block individual red-team IPs | OK |
| Spam password-change inject | **DO NOT** → DQ. Rate-limit ~1 change / 30 min. |
| Submit non-PDF inject | **WILL NOT BE GRADED** → 0 |
| Delete scoring/orange service accounts in AD | **DO NOT** → cascading red checks |
| AI agents | Allowed (free tier). You own blast radius. Out-of-scope scanning by your AI = DQ on you. |
| Real credentials anywhere on VMs | **DO NOT** — assume exfil |

## Timing

- **6h round**, plus **5min grace period** at start (no VM access, but portal + scoreboard accessible)
- Practice round: 2 days, no time limit, no red team, no orange team. Used to learn the portal.
- Scoring engine random interval ~2-3 min + ~2-3 min portal upload lag = ~5 min between change and visible status

## Q&A highlights from briefing

- Lab machines have internet
- Any free tools allowed. Scripts allowed. Private scripts allowed.
- VMs run in browser. VMRC console possible but unsupported / hacky (Workstation Player only, not Pro)
- AI fine as long as free-tier. Paid models / paid accounts not allowed.
- Last year's debrief video (awards stream, timestamped) is the highest-value prep resource per orgs.
