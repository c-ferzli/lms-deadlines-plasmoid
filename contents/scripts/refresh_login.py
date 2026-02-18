#!/usr/bin/env python3
import argparse
import os
import re
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

SESSKEY_RE = re.compile(r'"sesskey"\s*:\s*"([^"]+)"|sesskey\s*=\s*\'([^\']+)\'', re.I)

def has_sesskey(html: str) -> bool:
    return bool(SESSKEY_RE.search(html or ""))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--storage", required=True)
    ap.add_argument("--timeout-seconds", type=int, default=300)  # 5 min
    args = ap.parse_args()

    base = args.base_url.rstrip("/")
    dashboard_url = f"{base}/my/"

    storage = Path(os.path.expanduser(args.storage))
    storage.parent.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as pw:
        # 1) If storage exists, check headless whether it still logs in
        if storage.exists() and storage.stat().st_size > 50:
            try:
                req = pw.request.new_context(storage_state=str(storage))
                r = req.get(dashboard_url)
                if r.ok and has_sesskey(r.text()):
                    # refresh storage state (silent) and return
                    # Create a browser context only to write storage_state reliably:
                    browser = pw.chromium.launch(headless=True)
                    ctx = browser.new_context(storage_state=str(storage))
                    ctx.storage_state(path=str(storage))
                    ctx.close()
                    browser.close()
                    print("ALREADY_LOGGED_IN")
                    return 0
            except Exception:
                # treat as expired/invalid -> fall through to interactive login
                pass

        # 2) Interactive login (headed), auto-close once logged in
        browser = pw.chromium.launch(headless=False)
        ctx = browser.new_context(storage_state=str(storage) if storage.exists() else None)
        page = ctx.new_page()
        page.goto(dashboard_url, wait_until="domcontentloaded")

        deadline = time.time() + max(30, int(args.timeout_seconds))
        logged_in = False

        while time.time() < deadline:
            try:
                html = page.content()
                if has_sesskey(html):
                    logged_in = True
                    break
            except Exception:
                break
            time.sleep(2)

        if not logged_in:
            print("LOGIN_TIMEOUT_OR_WINDOW_CLOSED", file=sys.stderr)
            try:
                ctx.close()
                browser.close()
            except Exception:
                pass
            return 2

        ctx.storage_state(path=str(storage))
        ctx.close()
        browser.close()
        print("LOGGED_IN_SAVED")
        return 0

if __name__ == "__main__":
    raise SystemExit(main())
