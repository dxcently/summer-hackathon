# 00a — Newcomer primer

> Read this **first** if eCitadel / CCDC / blue-team competitions are new to you. Everything else in `docs/` assumes you already know the shape of the day. This doc gives you that shape.

## What kind of competition is this

eCitadel is a **blue-team defense competition** in the CCDC (Collegiate Cyber Defense Competition) tradition. You are not breaking into anything. You are *defending* a small fictional company's network for a few hours while:

- A **scoring engine** constantly pokes your services from outside and gives you points for keeping them working
- An **inject queue** drops business-memo tasks on you ("rotate all passwords", "write an account-lockout policy") that you have to complete and return as PDFs
- An **orange team** (simulated users) opens portal tickets at you that you have to reply to
- A **red team** (organizers' offensive operators) is *already inside your boxes* and is actively trying to break things
- A **CCS** (Cyber Competition System) agent runs on each box and silently grades your hardening / forensics work

Your job is to keep the lights on while doing the paperwork while kicking out attackers. It is mostly about **prioritization and triage**, not about being a genius hacker.

## The mental model in one paragraph

You are a brand-new IT/security team that just took over a network from people you don't trust. There is malware on every box. You have 6 hours. The CEO keeps emailing you memos (injects). Users keep filing tickets (orange team). Attackers keep popping shells (red team). The CEO doesn't care about the attackers — they care that the website works and that you answered the memos. Don't break the website while you clean up. Don't ignore the memos because you're chasing attackers.

## What a round actually feels like

- **Minute 0–5 (grace period):** You can see the portal but not the boxes. You read announcements, download the VPN config, skim already-delivered injects. **Calm.**
- **Minute 5–30:** You log into every box for the first time. You don't change anything yet. You look at users, processes, listening ports, scheduled tasks. You take notes. **Quiet panic.** Everything looks suspicious because you've never seen this baseline before.
- **Minute 30–90:** You disable obviously-bad accounts, kill obvious malware, change passwords via the password-change inject, start writing your first inject PDFs. **Loud panic.** Things break. Scoreboard goes red. You fix them. Things break again.
- **Minute 90–300:** Steady state. Loops: scoreboard every 5 min, inject portal every 10 min, orange tickets every 10 min. Red team waves arrive. You write IR reports. **Grind.**
- **Minute 300–360:** Wrap. Stop touching boxes 30 min before end. Submit ack-PDFs for unfinished injects. Watch scoreboard. **Sweaty.**

If you don't have the shape of the round in your head before T+0, you will spend the first 30 min in panic-mode chasing the first scary thing you see. Don't.

## Skills that actually matter (not what you'd guess)

Newcomers think the comp rewards 1337 hax. It does not. In rough order of points-per-minute:

1. **Reading carefully.** Inject deliverables are graded against the literal text of the inject. Miss a bullet, lose the point.
2. **Following instructions exactly.** Password-change format especially. Wrong format → silent ignore → cascading red.
3. **Knowing when NOT to change something.** Most service outages this comp will be self-inflicted by panicked teammates.
4. **Triage decisions.** "Is this red team or is this me?" "Is this upstream of another box?" "Is this worth a revert?"
5. **PDF-writing speed.** Yes, really. 35% of the score is injects, and a clean PDF beats a perfect technical fix that never gets written up.
6. **Basic OS admin** (find users, list ports, restart a service, edit a config). Not exploitation, not pen-testing.
7. **Logging discipline.** If you don't have notes, you don't have IR reports. No IR reports → can't claw back red team penalty.

## What your team should look like

5 people minimum. You can scrape by with 4 if the inject writer is fast.

| Role | What they do | Who suits it |
|---|---|---|
| **Lead / Triage** | Watches portal + scoreboard. Dispatches inject + ticket work. Does NOT touch boxes. | Someone calm, organized, fast reader |
| **Linux owner** | Owns Debian (Blacklist / DB) + Fedora (Concierge / web). | Anyone comfortable on a Linux shell |
| **Windows / AD owner** | Owns Cabal (Win Server / DC / DNS). The keystone box. | Someone with Active Directory / PowerShell exposure |
| **Network owner** | Owns pfSense + writes IR reports. | Someone who can read firewall rules without panicking |
| **Inject writer** | Turns evidence into PDFs. **Never touches a box.** | Someone who writes fast and follows instructions literally |

The **inject writer separation matters**. If your best writer is also fixing services, your PDFs slip and you lose 35% of the score chasing 35% of the score.

## The "do not freeze" rule

When the scoreboard goes red and an inject due-timer is ticking and orange team is yelling and red team just popped Cabal — newcomers freeze and try to fix everything at once. Don't.

The order is always:

1. **Stop new bleeding** (contain — but don't fix yet)
2. **Restore scored services** (because that meter never stops)
3. **Submit anything-shaped PDF** for the inject (even an ack — silence is worse)
4. **Then** harden, then IR-report, then everything else

If you can only do one thing in the next 60 seconds, do whichever is bleeding most. Everything else can wait 60 more seconds.

## Read these next, in this order

1. `docs/00-overview.md` — the official scoring breakdown + rules. The numbers tell you what to prioritize.
2. `docs/08-glossary.md` — every acronym in this folder, defined.
3. `docs/01-network.md` — the topology + IPs. Memorize the host roles.
4. `tasks/todo.md` — the actual run-of-show with a clock attached.
5. `docs/04-services.md` — the 7 scored services + dependency map. Cabal is the keystone — internalize that.
6. `docs/02-hardening.md` — your per-OS cheatsheet. Skim now, lean on it during the round.
7. `docs/03-injects.md` — inject SOP. Read the worked example at the bottom.
8. `docs/05-orange-team.md` — ticket SOP. Read the worked example.
9. `docs/06-red-team.md` — IR SOP. Read the worked example.
10. `docs/07-revert-policy.md` — when to revert, when not to. Decision tree.

If you only have 30 minutes to prep: read `00`, `08`, `tasks/todo.md`, and the IR example in `06`. The rest you can reference during the round.
