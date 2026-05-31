# 05 — Orange team SOP

> 10% of the score. New this year. Automated users hit your operations portal, submit tickets, and expect replies. Graded manually after the comp.

## How it works

- Orange team = automated users acting like RR Intel staff
- They **log in to your operations portal** using credentials you submitted via the password-change inject
- They **submit tickets** describing problems / requests
- They **expect a reply on the portal** in a reasonable time
- All replies are **graded by humans after the comp**

## How you lose points

1. They can't log in (you broke the portal, or wrong password submitted)
2. They submit a ticket and you don't reply in time
3. They submit a ticket and your reply is wrong / unhelpful
4. The portal's functionality drifts so far from baseline that the automation breaks

## Loop (every 10 minutes)

1. Open portal → operations portal tickets tab
2. Read any new tickets in order received
3. Reply in clear plain English, addressing the request
4. If the ticket is reporting a real issue (e.g., "I can't log in"), **fix it on the box AND reply**
5. Mark resolved if applicable

## Reply style guide

- Short, polite, factual
- Mirror the user's wording where helpful ("Your VPN access has been restored…")
- Include what was changed if it's user-facing
- Don't write status reports — they want a fix, not a postmortem

## Common ticket patterns to expect (anticipate)

| Ticket | Action |
|---|---|
| "Can't log in to portal" | Verify their account isn't locked / disabled; resubmit password-change if needed |
| "Need access to share X" | Add their account to the share group |
| "Reset my password" | Reset in AD; reply with temporary password — but **be careful about how you communicate it** (orange team can read replies) |
| "Service Y is slow / down" | Investigate; reply with what you found and ETA |
| "Policy compliance question" | Answer in plain English; don't over-engineer |

## What you must NOT do

- Don't delete orange-team user accounts in AD → cascading failures
- Don't change orange-team passwords outside the password-change inject flow → they won't sync
- Don't ignore tickets to focus on services → 10% is enough to flip rankings
- Don't break the portal aesthetic / form layout — automation parses fields, and "service changes too much from baseline → automation breaks → you lose points"

## Coordination with password-change inject

- Orange team and scoring engine **both** pull from your password-change submission
- If you fat-finger an orange-team user's password in the submission, that user can't log in for 30 min (until you can resubmit) → SLA-style loss
- Treat the password-change inject as the orange-team contract: every active user must be in it
