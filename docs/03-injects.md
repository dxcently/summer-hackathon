# 03 — Inject SOP

> **Injects are 35% of the score.** Every one needs a PDF response, even if it's "team didn't have capacity." Silence = penalty.

## How injects work

- Delivered on **rolling basis** via portal → Injects tab
- Each inject has: `Title`, `Start`, `Due`, `Reject` time, `Time Left`, `Score`, `Submitted` flag
- No notification — you must **poll the portal** (every 10 min minimum)
- Scoring instructions are inside the inject itself
- Past `Due` → submission closes, score is 0
- **Format: PDF only.** Word docs, screenshots, text files → not graded

## Roles for the inject loop

| Role | Responsibility |
|---|---|
| Triage lead | Monitors portal, classifies each inject, assigns owner |
| Box owner | Executes the technical work, captures evidence |
| Inject writer | Builds the PDF, ensures format compliance, submits |

The inject writer **does not touch boxes**. They sit out of the operational loop and own write-up quality.

## Per-inject workflow

1. **Read inject in full** — note exact deliverables, time due, scoring rubric
2. **Classify** — see below
3. **Assign** to a box owner + writer pair
4. **Execute** — owner performs work, writer takes screenshots / collects config + log evidence
5. **Draft PDF** in `templates/inject-response.md`, export
6. **Verify** PDF opens cleanly, file size sane (<5MB usually)
7. **Submit** via portal
8. **Confirm `Submitted: True`** before moving on
9. **Log** in your team note doc

## Inject classification (decide in <60 sec)

| Type | Examples | Priority |
|---|---|---|
| **Password change** | "Rotate all account passwords, submit in format X" | Top priority — affects orange team + scoring engine |
| **Configuration** | "Disable SMBv1", "Set MaxAuthTries=3" | High — usually quick + verifiable |
| **Forensic** | "Find the persistence mechanism on box X" | Medium — time-box to 30 min |
| **Compliance / policy** | "Write a 1-page policy for account lockout" | Low risk — pure writing |
| **Build / install** | "Install monitoring tool Y", "Set up SIEM logging" | Watch for risk of breaking services |

## Password-change inject (special)

This one is rate-limited and high-stakes:

- **Submission format is dictated in the inject** — read it word-for-word
- Includes service-engine + orange-team accounts (they pull from your submission)
- Rate limit ~ 1 change / 30 min — **do not spam, DQ risk**
- Submit **once**, with **all accounts**, in **exact format**
- If your format is wrong, portal silently ignores it → you change real passwords but scoring/orange still try the old ones → cascading red

Pre-comp action: study the **format spec** during the 5-min grace period before doing anything else.

## PDF tooling options

Pick one and stick with it:

- **Google Docs** → File → Download → PDF (zero install, works in Chrome)
- **Pandoc**: `pandoc inject-N.md -o inject-N.pdf --pdf-engine=xelatex`
- **Obsidian**: Export to PDF
- **Word / LibreOffice**: File → Export PDF

The PDF must:
- Open in a standard reader
- Have selectable text (not just an image scan)
- Include the inject ID / title at the top
- Include the team identifier

## Filing structure

For your own sanity, save a copy locally:

```
injects/
  YYYY-MM-DD/
    NN-<inject-title-slug>/
      inject.md          # source markdown
      inject.pdf         # what you submit
      evidence/          # screenshots, configs, logs
        before.png
        after.png
        config.diff
```

## Ack-PDF (when you can't deliver)

If the round is ending and you can't finish, submit something like:

```
Inject: <title>
Team: <team number>
Status: Acknowledged, not completed
Reason: Team did not have capacity to address this inject within
        the competition window due to higher-priority service-restoration
        work on <host>.
```

Better than 0. Some points awarded for showing the task force you saw the memo.

---

## Worked example: a real inject from start to PDF

> If you've never done an inject before, walk through this once. It uses a synthetic but representative inject. Every step is labeled with **who** does it.

### The inject (pretend it just appeared on the portal)

```
Title:       Disable SMBv1 on Cabal
Inject ID:   INJ-014
Start:       T+45 min
Due:         T+105 min  (60 min window)
Reject:      T+135 min
Score:       5
Submitted:   False

Body:
SMBv1 is a deprecated file-sharing protocol with well-known
credential-leak issues. Disable SMBv1 on the Cabal domain
controller and provide evidence (before/after) that the change
is in effect. Confirm SMB v2/v3 file shares remain functional.
```

### Step 1 — Triage lead reads + classifies (60 sec)

> Triage lead is the role from `docs/00a-newcomer-primer.md` who watches the portal and dispatches. They do not touch boxes.

The triage lead:

1. Reads the inject **in full**, including the body.
2. Classifies → **Configuration** (see classification table above). High priority — quick + verifiable.
3. Picks owner: Windows / AD owner (Cabal is theirs).
4. Picks writer: the inject writer (doesn't matter which box — they write, they don't touch).
5. Drops a note in the team chat / shared doc: `INJ-014 → @windows + @writer, due T+105`.

### Step 2 — Identify the literal deliverable (60 sec)

> Newcomers skip this. Don't. Read the inject body and pull out exactly what they're asking for.

This inject's deliverables:

1. SMBv1 is disabled on Cabal (proof required).
2. SMBv2/3 shares still work (proof required).
3. Before + after evidence.

That's three rubric items. Your PDF will have three pieces of evidence — one per item — or you'll lose points.

### Step 3 — Box owner captures BEFORE state (2 min)

> Always capture before-state first. If you change it without screenshotting first, you have no "before" to show, and the grader has to trust you. They won't.

On Cabal, in PowerShell as admin:

```powershell
# Before: SMBv1 status
Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
Get-SmbServerConfiguration | Select EnableSMB1Protocol
```

**Expected before-state output** (the bad state — what justifies the change):

```
FeatureName : SMB1Protocol
State       : Enabled

EnableSMB1Protocol : True
```

Box owner screenshots this. Saves the PNG to `injects/2026-MM-DD/INJ-014-disable-smbv1/evidence/before-smbv1-enabled.png`.

### Step 4 — Box owner makes the change (1 min)

```powershell
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
```

> `-NoRestart` matters. A reboot mid-comp risks knocking AD/DNS offline for several minutes → cascading red across multiple services. Defer reboots; the feature is disabled either way.

### Step 5 — Box owner captures AFTER state (2 min)

```powershell
Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
Get-SmbServerConfiguration | Select EnableSMB1Protocol

# Prove v2/v3 shares still work
Get-SmbShare
Test-NetConnection -ComputerName 172.21.0.103 -Port 445
```

**Expected after-state output**:

```
FeatureName : SMB1Protocol
State       : DisablePending      # disabled, will be removed on next reboot

EnableSMB1Protocol : False

Name      Path                  Description
----      ----                  -----------
NETLOGON  C:\Windows\SYSVOL\... Logon server share
SYSVOL    C:\Windows\SYSVOL     Logon server share

TcpTestSucceeded : True          # SMB v2/3 still serving
```

Screenshot. Save to `evidence/after-smbv1-disabled.png` and `evidence/after-smb-shares-listing.png`.

### Step 6 — Writer drafts the PDF (5–10 min)

> Writer opens `templates/inject-response.md`, fills in. Writer does NOT have to log into Cabal — they get the evidence files from the box owner via chat / shared drive.

Filled-in template (excerpt — full template is in `templates/inject-response.md`):

```markdown
# Inject Response — Disable SMBv1 on Cabal

**Team:** Team 17
**Inject ID:** INJ-014
**Submitted:** 2026-MM-DD HH:MM UTC
**Author(s):** @writer, @windows-owner

## Summary

Disabled SMBv1 on Cabal (172.21.0.103) via
`Disable-WindowsOptionalFeature` and `Set-SmbServerConfiguration`.
Verified SMBv1 reports as DisablePending and that SMBv2/v3 shares
(NETLOGON, SYSVOL) remain reachable on port 445. No reboot
performed; `-NoRestart` flag used to avoid AD outage.

## Acceptance criteria

- [x] SMBv1 disabled on Cabal — evidence below
- [x] SMBv2/v3 shares still functional — evidence below
- [x] Before + after evidence included

## Actions taken

1. Captured baseline (`Get-WindowsOptionalFeature -Online
   -FeatureName SMB1Protocol`) → SMB1Protocol State: Enabled.
2. Ran `Disable-WindowsOptionalFeature -Online
   -FeatureName SMB1Protocol -NoRestart`.
3. Ran `Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force`.
4. Captured post-change state → State: DisablePending,
   EnableSMB1Protocol: False.
5. Listed SmbShare + Test-NetConnection 445 → shares present,
   port reachable.

## Evidence

### Before
[before-smbv1-enabled.png attached]
Output: SMB1Protocol State: Enabled. EnableSMB1Protocol: True.

### After
[after-smbv1-disabled.png attached]
Output: SMB1Protocol State: DisablePending. EnableSMB1Protocol: False.

### Verification (v2/v3 still working)
[after-smb-shares-listing.png attached]
NETLOGON + SYSVOL shares present. TcpTestSucceeded: True on 445.

## Side effects + risk

- DisablePending — SMBv1 fully removed only after next reboot.
  Intentional deferral to avoid AD/DNS outage mid-round.
- No user-facing impact expected — comp environment uses no
  legacy SMBv1 clients.

## Rollback plan

`Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart`
then `Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force`.
```

### Step 7 — Export to PDF (1 min)

Pick whichever tool you pre-staged. Pandoc example:

```bash
pandoc INJ-014.md \
  --pdf-engine=xelatex \
  -V geometry:margin=1in \
  -o INJ-014-disable-smbv1.pdf
```

Open the PDF locally. **Verify**:
- It opens in a standard reader.
- Text is selectable (not just a screenshot of text).
- Images embedded correctly (open each image in the PDF, look for missing-image boxes).
- Inject ID and team number visible at the top.
- File size sane (under 5 MB usually).

### Step 8 — Submit via portal (1 min)

1. Portal → Injects tab → INJ-014 → Upload Response.
2. Choose your PDF.
3. Submit.
4. **Verify** `Submitted: True` flips. Refresh once.
5. If it didn't flip — wrong file selected, network blip, or upload failed silently. Retry.

### Step 9 — Log it (30 sec)

In your team's shared note doc:

```
T+89 — INJ-014 submitted (SMBv1 disabled on Cabal).
       Submitted: True confirmed.
       Files: injects/2026-MM-DD/INJ-014-disable-smbv1/
```

### Total time: ~15 minutes

The writer does steps 1, 2, 6, 7. The box owner does 3, 4, 5. Triage lead does step 8 (submit) so the role doing technical work isn't the role pressing the button — separation of concerns reduces "I uploaded the wrong file" mistakes.

If the inject window is 60 min and this takes you 15, you have 45 min of buffer for the next inject, the orange ticket queue, or the next red-team wave. **That buffer is the whole game.** Lose it once and you're chasing.
