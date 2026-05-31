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

---

## Worked example: handling a portal ticket end-to-end

> Walk through this once if you've never replied to an automated-user ticket. The example is synthetic but representative.

### The incoming ticket (pretend you just saw this on the portal)

```
Ticket ID:    TICKET-0042
Opened:       2026-MM-DD 14:42 UTC
From:         j.morales@rrintel.internal
Subject:      Can't reach internal wiki from VPN
Body:
  I came back from lunch and the internal wiki at
  https://wiki.rrintel.internal/ won't load — browser hangs
  then times out. My VPN says it's connected. Other coworkers
  can hit it fine. Help?
```

### Step 1 — Read the whole ticket (30 sec)

> Newcomers skim, then guess. Don't. Read it twice.

Pull the key facts out of the body:

- The user: `j.morales` — likely an AD account, listed in your password-change submission
- The symptom: hangs then times out (not "unauthorized", not "cert error" — pure network reach)
- Their context: VPN says connected, **coworkers can reach the site**

The last point is the diagnostic key. If coworkers can reach it, the wiki itself is up. Either j.morales's session is bad, their account is locked, or something at the firewall is dropping just their traffic.

### Step 2 — Verify before you reply (3 min)

> Don't reply with "I fixed it" before you've actually fixed it. Auto-grader can't tell, but the human grader after the comp will compare your reply to the box state.

Linux/Windows owner checks:

```powershell
# On Cabal — is the user locked?
Get-ADUser j.morales -Properties LockedOut,Enabled,LastLogonDate,LastBadPasswordAttempt
```

```bash
# On Concierge (web host for the wiki) — recent auth failures for this user?
journalctl -u httpd --since "30 min ago" | grep -i 'j.morales'
grep 'j.morales' /var/log/nginx/access.log | tail -n 20
```

You see:

```
LockedOut             : True
LastBadPasswordAttempt : 14:35 UTC
```

The account is locked. AD lockout policy kicked in after N failed password attempts at 14:35 — 7 minutes before the ticket arrived. Most likely cause: a cached old password on the user's browser auto-retrying after your password-change submission, tripping lockout.

### Step 3 — Fix the underlying issue (2 min)

```powershell
# Unlock the account (do not reset the password — orange team
# still has the new one from your password-change submission)
Unlock-ADAccount -Identity j.morales

# Verify
Get-ADUser j.morales -Properties LockedOut
# → LockedOut : False
```

### Step 4 — Reply on the portal (2 min)

> Short, polite, factual. Mirror their wording. Tell them what changed *from their perspective*, not the technical detail.

```
Hi j.morales,

Your account was locked due to repeated failed logins
(likely a cached old password retrying after our recent
account-security update). I've unlocked the account.

Please close any browser tabs to the wiki, then sign in
again. If the wiki still won't load after a fresh sign-in,
reply here and we'll dig further.

— Team 17 IT
```

What this reply does well:

- **Plain English**, no jargon (`LockedOut`, `LastBadPasswordAttempt` would mean nothing to the user)
- **Tells them what changed** (unlocked) — they don't have to guess if action was taken
- **Tells them what to do next** (close tabs, sign in again)
- **Leaves the door open** for a followup — not a hard close
- **Does NOT include a password** in plain text (orange team can read replies → never paste credentials)

### Step 5 — Verify the fix from the user's side (1 min)

Box owner does a quick check that the wiki itself is healthy:

```bash
curl -ks https://172.27.17.102/wiki/ -o /dev/null -w '%{http_code}\n'
# → 200
```

And the scored web service is green on the scoreboard.

### Step 6 — Log + close (30 sec)

In your team's running log:

```
T+102 — TICKET-0042 (j.morales / wiki unreachable) replied.
        Cause: AD lockout from cached old password.
        Action: Unlock-ADAccount. Replied with sign-in
        instructions. Wiki externally green.
```

Mark resolved on the portal.

### Total time: ~9 minutes

The most common newcomer mistake on tickets is to **just reply** without checking the box, or **just fix** without replying. The orange team scoring expects both. The human grader after the comp will downgrade replies that don't match what actually happened on the system — and downgrade fixes that left the user without a response.

A useful loop heuristic: every ticket gets **one reply within 10 min** even if it's "looking into this now, will update". Silence for 10+ min on any ticket = points lost.
