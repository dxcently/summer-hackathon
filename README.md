# eCitadel Season IV — RR Intel Task Force

Personal prep workspace for the eCitadel S4 blue-team competition (CCS-style: find/fix vulns + scored services + injects + orange team + red team penalty).

## Start here

1. `tasks/todo.md` — the actual run-of-show plan with timeline + checklists
2. `docs/00-overview.md` — scenario + scoring breakdown
3. `docs/01-network.md` — topology, IPs, NAT, scoring engine notes
4. `docs/02-hardening.md` — per-box hardening cheatsheet
5. `docs/03-injects.md` — inject SOP + PDF rules
6. `docs/04-services.md` — the 7 scored services + dependency map
7. `docs/05-orange-team.md` — ticket SOP
8. `docs/06-red-team.md` — IR + instant report SOP
9. `docs/07-revert-policy.md` — when to revert, when not to
10. `templates/inject-response.md` — copy-paste PDF template
11. `templates/ir-report.md` — instant report template

## Source material

- `brief-ts-1.txt`, `brief-ts-2.txt`, `brief-ts-3.txt` — auto-captured briefing transcript
- `ecitadel-screenshots-01.png` … `08.png` — briefing slides (note: numbered in reverse, 08 = first slide chronologically)

## Constraints to remember

- 6h round + 5min grace
- All VMs via browser (Chrome). WireGuard VPN access available after start.
- 4 reverts/team free, more = penalty
- PDF-only inject responses. Submit something for every inject (even an ack).
- Never scan .1/.2 on your subnet, never scan other teams or red team → DQ
- AI tools allowed (free tier only) but YOU own its blast radius
