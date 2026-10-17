"""Shared measurement contract regressions; no build, device or sampling."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import pytest

ENTRY = Path(__file__).with_name("measure_platforms.py")
SPEC = importlib.util.spec_from_file_location("notihub_measure_entry", ENTRY)
entry = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(entry)


class PlatformDefaultTests(unittest.TestCase):
    def command(self, args=(), environment=None):
        with patch.dict(os.environ, environment or {}, clear=True):
            return entry.command(list(args))

    def test_default_all_and_persisted_single_platform(self):
        default = self.command()
        selected = self.command(environment={"SOP_PERF_PLATFORM": "iphone"})
        self.assertEqual(default[-2:], ["--platform", "all"])
        self.assertEqual(selected[-2:], ["--platform", "iphone"])
        self.assertEqual(default[:-2], selected[:-2])
        for value in ("day-deck-ios", "--fixture-debug", "--sync-ios"):
            self.assertIn(value, selected)

    def test_explicit_platform_overrides_environment(self):
        for args in (("--platform", "vision"), ("--platform=vision",)):
            with self.subTest(args=args):
                command = self.command(args, {"SOP_PERF_PLATFORM": "invalid"})
                self.assertEqual(command[-len(args):], list(args))
                self.assertNotIn("invalid", command)
                self.assertNotIn("all", command)

    def test_invalid_environment_stops_before_exec(self):
        with patch.dict(os.environ, {"SOP_PERF_PLATFORM": "mac"}, clear=True), \
                patch.object(entry, "load_tool") as load:
            with self.assertRaises(SystemExit):
                entry.main([])
        load.assert_not_called()


@pytest.mark.parametrize("failure,expected", [
    ("catalog_timeout", 75), ("raw_timeout", 75), ("busy", 75),
    ("catalog_nonzero", 1), ("ready_timeout", 1), ("assertion", 1),
    ("source_changed", 1),
])
def test_original_all_mode_defers_once_and_never_writes_evidence(tmp_path, monkeypatch, failure, expected):
    """Exercise the real shared all/main handlers with synthetic SDK candidates."""
    shared = entry.load_tool()
    lane = shared.sim_lane
    (tmp_path / "project.yml").write_text("synthetic test project")
    monkeypatch.setattr(shared, "lane_config", lambda *a: {"component": "mac-owner"} if a[-1] == "mac" else {})
    monkeypatch.setattr(shared, "lane_inputs", lambda *a: "current-production-input")
    monkeypatch.setattr(shared, "current_evidence", lambda *a: None)
    monkeypatch.setattr(shared, "default_scheme", lambda *a: "DayDeck")
    builds, measured, writes = [], [], []

    def cached(app, repo, platform, scheme, fixture, leases):
        builds.append((platform, fixture))
        return {"app_path": str(tmp_path / "Synthetic.app"), "bundle_id": "test.notihub"}

    def simctl(*args, **kwargs):
        if failure == "catalog_timeout":
            raise lane.LaneError("xcrun simctl list devicetypes 超过 120s")
        if failure == "raw_timeout":
            raise subprocess.TimeoutExpired(["xcrun", "simctl", *args], 120)
        if failure == "busy":
            raise lane.Busy("memory pressure / quiet gate")
        raise lane.LaneError("xcrun simctl list devicetypes rc=1: unavailable runtime")

    def measure(platform, *args):
        measured.append(platform)
        if failure == "ready_timeout":
            raise lane.LaneError("App lane-ready 超时")
        if failure == "assertion":
            raise lane.LaneError("HTTP 500 / product assertion failed")
        if failure == "source_changed":
            raise SystemExit("测量期间平台线输入变了，未写证据")
        lane.simctl("list", "devicetypes")

    monkeypatch.setattr(shared, "cached_build", cached)
    monkeypatch.setattr(shared, "size_of", lambda *a: {})
    monkeypatch.setattr(shared, "measure_sim", measure)
    monkeypatch.setattr(shared, "write_evidence", lambda *a: writes.append(a))
    monkeypatch.setattr(lane, "simctl", simctl)
    monkeypatch.setattr(entry, "ROOT", tmp_path)
    monkeypatch.setattr(entry, "load_tool", lambda: shared)
    monkeypatch.delenv("SOP_PLATFORM_REUSE_BUILDS", raising=False)
    monkeypatch.delenv("SOP_PLATFORM_REUSE_BUILDS_SHA256", raising=False)
    monkeypatch.delenv("SOP_PLATFORM_POSTBOOT_LOAD_WAIT", raising=False)
    monkeypatch.delenv("SOP_PERF_PLATFORM", raising=False)
    assert entry.main(["--platform", "all", "--lock-wait", "0", "--load-wait", "0"]) == expected
    assert writes == []
    assert lane.simctl is simctl  # Scoped adapter restores the shared function.
    if expected == 75:
        assert measured == ["iphone"]
        assert builds == [("iphone", False), ("iphone", True)]
    else:
        assert measured == ["iphone", "ipad", "watch", "vision"]


def test_adapter_keeps_current_evidence_skip_and_shared_success(tmp_path, monkeypatch):
    shared = entry.load_tool()
    (tmp_path / "project.yml").write_text("synthetic test project")
    monkeypatch.setattr(entry, "ROOT", tmp_path)
    monkeypatch.setattr(entry, "load_tool", lambda: shared)
    monkeypatch.setattr(shared, "lane_config", lambda *a: {"component": "mac-owner"} if a[-1] == "mac" else {})
    monkeypatch.setattr(shared, "lane_inputs", lambda *a: "current-production-input")
    monkeypatch.setattr(shared, "current_evidence", lambda *a: {"verified": True})
    with patch.object(shared, "sync_ios_evidence") as sync, patch.object(shared, "cached_build") as build:
        assert entry.main(["--platform", "all"]) == 0
    sync.assert_called_once_with(tmp_path, {"verified": True})
    build.assert_not_called()


def test_adapter_does_not_hide_non_catalog_timeouts(monkeypatch):
    shared = entry.load_tool()
    lane = shared.sim_lane
    error = lane.LaneError("xcrun simctl launch owned 超过 60s")
    with patch.object(lane, "simctl", side_effect=error) as original:
        with entry.defer_catalog_timeouts(lane):
            with pytest.raises(lane.LaneError) as caught:
                lane.simctl("launch", "owned", "test.bundle", timeout=60)
        assert lane.simctl is original
    assert caught.value is error


if __name__ == "__main__":
    unittest.main()
