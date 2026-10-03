#!/usr/bin/env python3
"""Notihub: forward one persisted platform to the original shared measurer."""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = Path.home() / "Apps/.claude/skills/app-lightweight/scripts/platform_measure.py"
args = sys.argv[1:]
platform = []
if "--platform" not in args and not any(a.startswith("--platform=") for a in args):
    selected = os.environ.get("SOP_PERF_PLATFORM") or "all"
    if selected not in ("iphone", "ipad", "watch", "vision", "all"):
        raise SystemExit(f"invalid SOP_PERF_PLATFORM: {selected}")
    platform = ["--platform", selected]
os.execv(sys.executable, [sys.executable, str(TOOL), "--app", "day-deck-ios", "--repo", str(ROOT),
                         "--fixture-debug", "--sync-ios", *platform, *args])
