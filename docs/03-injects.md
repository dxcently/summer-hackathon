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
