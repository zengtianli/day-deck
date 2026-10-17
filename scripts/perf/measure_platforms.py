#!/usr/bin/env python3
"""Notihub: run the original shared measurer with catalog timeout deferral."""
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = Path.home() / "Apps/.claude/skills/app-lightweight/scripts/platform_measure.py"
sys.path.insert(0, str(ROOT / "scripts"))
from simulator_environment import defer_catalog_timeouts


def command(args):
    platform = []
    if "--platform" not in args and not any(a.startswith("--platform=") for a in args):
        selected = os.environ.get("SOP_PERF_PLATFORM") or "all"
        if selected not in ("iphone", "ipad", "watch", "vision", "all"):
            raise SystemExit(f"invalid SOP_PERF_PLATFORM: {selected}")
        platform = ["--platform", selected]
    return ["--app", "day-deck-ios", "--repo", str(ROOT),
            "--fixture-debug", "--sync-ios", *platform, *args]


def load_tool():
    spec = importlib.util.spec_from_file_location("notihub_platform_measure", TOOL)
    measure = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(measure)
    return measure


def main(argv=None):
    args = command(list(sys.argv[1:] if argv is None else argv))
    measure = load_tool()
    # Keep the original cache, evidence writer, input binding, BuildSlot and
    # Session quiet gates; all-mode sees 75 and stops at the deferred platform.
    with defer_catalog_timeouts(measure.sim_lane):
        return measure.main(args)


if __name__ == "__main__":
    raise SystemExit(main())
