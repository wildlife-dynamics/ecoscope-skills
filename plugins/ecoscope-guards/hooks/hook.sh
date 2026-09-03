#!/usr/bin/env bash
# hook.sh <script.py> — the entry point every ecoscope-guards hook goes through.
# Fails open: without python3 there is no guard, because a hook that errors on every tool call is
# worse than no hook at all.
set -u
command -v python3 >/dev/null 2>&1 || exit 0
exec python3 "$(dirname "$0")/$1"
