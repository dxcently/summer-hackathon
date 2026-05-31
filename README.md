# eCitadel Season IV — RR Intel Task Force

Personal prep workspace for the eCitadel S4 blue-team competition (CCS-style: find/fix vulns + scored services + injects + orange team + red team penalty).

## Start here

**New to CCDC-style blue-team comps?** Read `docs/00a-newcomer-primer.md` first — it frames the whole round so the rest of the docs land. Then `docs/08-glossary.md` so the acronyms in the other docs are decoded.

1. `docs/00a-newcomer-primer.md` — **start here if you're new.** Mental model + what a round actually feels like
2. `docs/08-glossary.md` — every acronym + term used in this folder
3. `tasks/todo.md` — the actual run-of-show plan with timeline + checklists
4. `docs/00-overview.md` — scenario + scoring breakdown
5. `docs/01-network.md` — topology, IPs, NAT, scoring engine notes
6. `docs/02-hardening.md` — per-box hardening cheatsheet
7. `docs/03-injects.md` — inject SOP + PDF rules (includes a fully walked-through example at the bottom)
8. `docs/04-services.md` — the 7 scored services + dependency map
9. `docs/05-orange-team.md` — ticket SOP (includes a walked-through ticket example at the bottom)
10. `docs/06-red-team.md` — IR + instant report SOP (includes a walked-through webshell-IR example at the bottom)
11. `docs/07-revert-policy.md` — when to revert, when not to
12. `templates/inject-response.md` — copy-paste PDF template
13. `templates/ir-report.md` — instant report template

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
