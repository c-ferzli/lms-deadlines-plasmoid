# LMS Deadlines Plasmoid

A KDE Plasma widget that pulls LMS deadlines into your panel popup, with separate **Homeworks** and **Quizzes** views.

It is built for Moodle-based LMS pages and tuned for practical student use:
- quick session-based login
- clean upcoming list with time remaining
- quiz/midterm extraction from course pages and syllabus PDFs
- one-command release packaging to GitHub

## What It Shows

- **Homeworks tab**: upcoming assignment deadlines from LMS calendar/actions.
- **Quizzes tab**: upcoming quiz and midterm dates extracted from:
  1. course pages (authoritative)
  2. syllabus PDFs (fallback)

The popup is optimized for fast scanning:
- course name
- assessment title
- due text (date/time/location when available)
- time remaining

## Current Behavior

- Quiz refresh is fixed to **1 hour**.
- Homework refresh remains configurable in widget settings.
- Desktop popup notifications are disabled (widget-only workflow).
- Compact badge shows **homework count only**.

## Install / Update (from zip)

Use the packaged file in this repo root:

- `com.chris.lmsdeadlines.zip`

Install with your preferred Plasma method (e.g. *Add Widgets* / *Install from File*).

## Login Flow

The widget uses a saved Playwright storage session.
If your LMS session expires, use **Login to LMS** in widget UI and complete login in the opened browser window.

## Project Structure

- `contents/ui/main.qml` - main widget UI and refresh logic
- `contents/ui/configGeneral.qml` - settings UI
- `contents/config/main.xml` - stored config entries
- `contents/scripts/extract_deadlines.py` - homework extraction
- `contents/scripts/extract_quizzes.py` - quiz/midterm extraction
- `contents/scripts/refresh_login.py` - session refresh/login
- `contents/scripts/run_deadlines.sh` - wrapper entrypoint

## Release Workflow

A helper command is provided on the author machine:

```bash
releasezip "your commit message"
```

It will:
1. build a clean `com.chris.lmsdeadlines.zip`
2. update the tracked zip in this repo
3. remove legacy zip name if present
4. commit and push to `main`

If no package content changed, it exits with:

`No zip changes to commit.`

## Troubleshooting

### Quiz date looks wrong
- Often caused by noisy course-page text blocks.
- Parser currently prefers postponement/reschedule wording and filters common Moodle activity noise.

### Missing quiz/midterm
- Check if date is outside selected quiz window (7/14/30 days).
- Some courses only expose dates in PDFs; extraction depends on readable syllabus content.

### UI text overlap
- Remaining-time text is rendered in a high-contrast pill and due text is elided when needed.

## Notes

This repository currently tracks the packaged artifact (`.zip`) for easy install/update distribution.
