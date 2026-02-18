#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${LMS_VENV_DIR:-$HOME/.local/share/lmsdeadlines/venv}"
PY="$VENV_DIR/bin/python"

mkdir -p "$(dirname "$VENV_DIR")"

# Create venv if missing
if [ ! -x "$PY" ]; then
  python3 -m venv "$VENV_DIR"
fi

# Ensure pip is usable inside venv
"$PY" -m pip install -U pip setuptools wheel

# Ensure playwright is installed in venv
if ! "$PY" -c "import playwright" >/dev/null 2>&1; then
  "$PY" -m pip install -U playwright
fi

# Ensure browser binaries
"$PY" -m playwright install chromium

exec "$PY" "$@"
