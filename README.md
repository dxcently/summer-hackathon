# Season IV — RR Intel Task Force

Personal prep workspace for the S4 blue-team competition (CCS-style: find/fix vulns + scored services + injects + orange team + red team penalty).

## Start here

**New to CCDC-style blue-team comps?** Read `docs/00a-newcomer-primer.md` first — it frames the whole round so the rest of the docs land. Then `docs/08-glossary.md` so the acronyms in the other docs are decoded. If you've never done a practice round, walk `docs/09-practice-round-walkthrough.md` before competition day — same shape of work, easier difficulty, no time pressure.

1. `docs/00a-newcomer-primer.md` — **start here if you're new.** Mental model + what a round actually feels like
2. `docs/08-glossary.md` — every acronym + term used in this folder
3. `docs/09-practice-round-walkthrough.md` — methodology guide for the practice round (Mint 21 / Alma 9 / Win Server 2016 / pfSense). No answers
4. `tasks/todo.md` — the actual run-of-show plan with timeline + checklists
5. `docs/00-overview.md` — scenario + scoring breakdown
6. `docs/01-network.md` — topology, IPs, NAT, scoring engine notes
7. `docs/02-hardening.md` — per-box hardening cheatsheet
8. `docs/03-injects.md` — inject SOP + PDF rules (includes a fully walked-through example at the bottom)
9. `docs/04-services.md` — the 7 scored services + dependency map
10. `docs/05-orange-team.md` — ticket SOP (includes a walked-through ticket example at the bottom)
11. `docs/06-red-team.md` — IR + instant report SOP (includes a walked-through webshell-IR example at the bottom)
12. `docs/07-revert-policy.md` — when to revert, when not to
13. `templates/inject-response.md` — copy-paste PDF template
14. `templates/ir-report.md` — instant report template

## Scripts

All read-only, organized by lifecycle phase. See `scripts/README.md` for the full operator guide (cadence, diffing, evidence handling).

- `scripts/bootstrap/` — first-run setup. `bootstrap-debian.sh` (Blacklist), `bootstrap-fedora.sh` (Concierge). Installs a FOSS toolkit, creates `~/.rrintel/`, stages the triage + watchdog scripts. Windows + pfSense are manual checklists in `scripts/bootstrap/README.md`
- `scripts/triage/` — read-only state captures. `linux-triage.sh`, `windows-triage.ps1`, `pfsense-triage.sh` for per-box baselines; `external-check.sh` for outside-pfSense probing; `first-run-checks.sh` for a 60-second sanity sweep post-bootstrap; `check-network.sh` / `check-services.sh` for focused re-checks; `compare-triage.sh` to diff two triage logs with PID/timestamp noise stripped; `ir-capture.sh` for full evidence packs on a suspect PID *before* you kill it
- `scripts/watchdog/` — observe-only background daemons. `watchdog-linux.sh`, `watchdog-pfsense.sh`. Baseline once, log only deltas. Never modifies state

All outputs land in a hidden workdir (`~/.rrintel/` on Linux, `/root/.rrintel/` on pfSense, `%USERPROFILE%\.rrintel\` on Windows) with `chmod 700`.

## Source material

- `S4_Orientation.pdf` — official orientation deck
- `S4_Practice_Round_README.pdf` — practice round brief
- `S4_Practice_Round_Mint21_Answer_Key.pdf`, `…_Alma9_Answer_Key.pdf`, `…_Win2016_Answer_Key.pdf` — practice answer keys. **Don't read until you've worked the box.** Walkthrough methodology lives in `docs/09-practice-round-walkthrough.md`
- `brief-ts-1.txt`, `brief-ts-2.txt`, `brief-ts-3.txt` — auto-captured briefing transcript
- `briefing-01.png` … `08.png` — briefing slides (note: numbered in reverse, 08 = first slide chronologically)

## Constraints to remember

- 6h round + 5min grace
- All VMs via browser (Chrome). WireGuard VPN access available after start.
- 4 reverts/team free, more = penalty
- PDF-only inject responses. Submit something for every inject (even an ack).
- Never scan .1/.2 on your subnet, never scan other teams or red team → DQ
- AI tools allowed (free tier only) but YOU own its blast radius
