#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

from playwright.sync_api import sync_playwright

IGNORE_RE = re.compile(r"\b(in[\s-]*lab|quiz)\b", re.IGNORECASE)

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--plain", action="store_true")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--overdue-cutoff-days", type=int, default=1)
    p.add_argument("--base-url", default=os.environ.get("LMS_BASE_URL", "https://lms.aub.edu.lb"))
    p.add_argument("--storage", default=os.environ.get("LMS_STORAGE_STATE", "~/.local/share/lmsdeadlines/storage_state.json"))
    return p.parse_args()

ARGS = parse_args()

def notify(title: str, message: str, urgency: str = "normal") -> None:
    if ARGS.plain:
        return
    subprocess.run(["notify-send", "-u", urgency, title, message], check=False)

def time_remaining_plain(due: datetime) -> str:
    now = datetime.now()
    delta = due - now
    if delta.total_seconds() < 0:
        return "OVERDUE"
    days = delta.days
    hours, rem = divmod(delta.seconds, 3600)
    minutes = rem // 60
    parts = []
    if days: parts.append(f"{days}d")
    if hours: parts.append(f"{hours}h")
    if not days and not hours: parts.append(f"{minutes}m")
    return " ".join(parts)

def extract_sesskey(html: str) -> str | None:
    m = re.search(r'"sesskey"\s*:\s*"([^"]+)"', html)
    if m: return m.group(1)
    m = re.search(r"sesskey\s*=\s*'([^']+)'", html)
    if m: return m.group(1)
    return None

def call_ajax(reqctx, ajax_url: str, sesskey: str, function_name: str, args: dict):
    payload = [{"index": 0, "methodname": function_name, "args": args}]
    r = reqctx.post(f"{ajax_url}?sesskey={sesskey}&info={function_name}", data=payload)
    if not r.ok:
        raise RuntimeError(f"AJAX HTTP {r.status} calling {function_name}")
    return r.json()

def pick_course_name(ev: dict) -> str:
    for k in ("coursefullname", "coursename", "course", "courseShortName"):
        v = ev.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    c = ev.get("course")
    if isinstance(c, dict):
        for k in ("fullname", "shortname", "name"):
            v = c.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()
    return "(Unknown course)"

def pick_title(ev: dict) -> str:
    for k in ("name", "title", "activityname", "instancename"):
        v = ev.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return "(Untitled)"

def pick_due(ev: dict) -> datetime | None:
    for k in ("timesort", "timestart", "time", "duedate", "timedue"):
        v = ev.get(k)
        if isinstance(v, (int, float)) and v > 0:
            return datetime.fromtimestamp(v)
    return None

def looks_completed(ev: dict) -> bool:
    if ev.get("completed") is True or ev.get("iscompleted") is True:
        return True
    v = ev.get("completionstate")
    if isinstance(v, int) and v != 0:
        return True
    for k in ("status", "submissionstatus"):
        vv = ev.get(k)
        if isinstance(vv, str) and re.search(r"submitted|graded|done|complete", vv, re.I):
            return True
    return False

def main() -> int:
    base = ARGS.base_url.rstrip("/")
    dashboard_url = f"{base}/my/"
    ajax_url = f"{base}/lib/ajax/service.php"

    # IMPORTANT: expand ~ and require it to exist
    storage_path = Path(os.path.expanduser(ARGS.storage))

    if not storage_path.exists() or storage_path.stat().st_size < 50:
        print(
            "Not logged in (cookie file missing/empty).\n"
            "Open widget Settings → Login → 'Login once (save cookies)'.\n"
            f"Expected cookie file: {storage_path}",
            file=sys.stderr
        )
        return 2

    deadlines = []

    with sync_playwright() as p:
        try:
            reqctx = p.request.new_context(storage_state=str(storage_path))
        except Exception as e:
            print(
                "Cookie file could not be loaded. Delete it and run Login once again.\n"
                f"Cookie file: {storage_path}\n"
                f"Error: {e}",
                file=sys.stderr
            )
            return 2

        dash = reqctx.get(dashboard_url)
        if not dash.ok:
            print(f"Failed to load dashboard: HTTP {dash.status}", file=sys.stderr)
            return 2

        sesskey = extract_sesskey(dash.text())
        if not sesskey:
            print("No sesskey found; you may be logged out. Run Login once again.", file=sys.stderr)
            return 2

        functions = [
            "core_calendar_get_action_events_by_timesort",
            "core_calendar_get_action_events_by_course",
            "core_calendar_get_calendar_upcoming_view",
        ]

        data = None
        last_err = None
        for fn in functions:
            try:
                data = call_ajax(reqctx, ajax_url, sesskey, fn, {"limitnum": int(ARGS.limit), "timesortfrom": 0})
                break
            except Exception as e:
                last_err = e

        if data is None:
            print(f"All AJAX attempts failed: {last_err}", file=sys.stderr)
            return 2

        call0 = data[0]
        if call0.get("error"):
            msg = call0.get("exception") or call0.get("message") or "Unknown AJAX error"
            print(f"AJAX returned error: {msg}", file=sys.stderr)
            return 2

        payload = call0.get("data") or {}
        events = []
        if isinstance(payload, dict):
            if isinstance(payload.get("events"), list):
                events = payload["events"]
            elif isinstance(payload.get("actionevents"), list):
                events = payload["actionevents"]
            elif isinstance(payload.get("eventsbyday"), list):
                for day in payload["eventsbyday"]:
                    if isinstance(day, dict) and isinstance(day.get("events"), list):
                        events.extend(day["events"])

        cutoff = datetime.now() - timedelta(days=int(ARGS.overdue_cutoff_days))

        for ev in events:
            if not isinstance(ev, dict):
                continue
            title = pick_title(ev)
            if IGNORE_RE.search(title):
                continue
            due = pick_due(ev)
            if not due or due < cutoff:
                continue
            if looks_completed(ev):
                continue
            deadlines.append((pick_course_name(ev), title, due))

    deadlines.sort(key=lambda x: x[2])

    if not deadlines:
        print("No upcoming deadlines")
        return 0

    for course, title, due in deadlines:
        due_str = due.strftime("%Y-%m-%d %H:%M")
        rem = time_remaining_plain(due)
        print(f"{course} | {title} | {due_str} | {rem}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
