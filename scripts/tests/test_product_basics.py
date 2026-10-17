"""Candidate/evidence safety only; no build, simulator or network access."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

ACCEPT = Path(__file__).resolve().parents[1] / "accept"
SPEC = importlib.util.spec_from_file_location("notihub_product_basics_test", ACCEPT / "product_basics.py")
basics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(basics)


@pytest.fixture
def candidate(tmp_path, monkeypatch):
    receipt = tmp_path / "build-receipt.json"
    built = {"ok": True, "app_path": str(tmp_path / "Current.app"), "build": "9"}
    verified = {**built, "reuse": {"input_sha256": "verified-current-production"}}
    reuse = Mock(return_value=verified)
    build = Mock(return_value=built)
    monkeypatch.setattr(basics, "RECEIPT", receipt)
    monkeypatch.setattr(basics.sim_lane, "reuse_build", reuse)
    monkeypatch.setattr(basics.sim_lane, "build", build)
    args = SimpleNamespace(receipt=None, app=None, rebuild=False)
    return SimpleNamespace(args=args, receipt=receipt, built=built, verified=verified, reuse=reuse, build=build)


def test_valid_automatic_candidate_reuses_without_build(candidate):
    c = candidate
    c.receipt.write_text("original receipt")
    assert basics.candidate(c.args) == (Path(c.built["app_path"]), c.receipt, c.verified)
    c.build.assert_not_called()
    assert c.receipt.read_text() == "original receipt"


@pytest.mark.parametrize("reason", [
    "缓存构建无法核验：source globs 没有匹配任何实际构建输入",
    "缓存构建源码与当前平台输入不同", "缓存产物的可执行文件已变化",
])
def test_stale_automatic_candidate_rebuilds_then_strictly_verifies(candidate, reason):
    c = candidate
    c.receipt.write_text("stale receipt")
    c.reuse.side_effect = [basics.sim_lane.LaneError(reason), c.verified]
    assert basics.candidate(c.args)[2] == c.verified
    c.build.assert_called_once_with(basics.ROOT, "DayDeck", "iphone", "Debug")
    assert json.loads(c.receipt.read_text()) == c.built
    assert c.reuse.call_count == 2
    for call in c.reuse.call_args_list:
        assert call.args == (c.receipt, "day-deck-ios", basics.ROOT, "iphone", "DayDeck", "Debug")


def test_missing_automatic_receipt_builds_and_verifies_before_use(candidate):
    c = candidate
    assert basics.candidate(c.args)[2] == c.verified
    c.build.assert_called_once()
    c.reuse.assert_called_once()


def test_explicit_bad_receipt_cannot_silently_rebuild_or_trust_sop_flag(candidate, monkeypatch):
    c = candidate
    c.args.receipt, c.args.app = c.receipt, Path(c.built["app_path"])
    c.receipt.write_text("explicit receipt")
    c.reuse.side_effect = basics.sim_lane.LaneError("production input changed")
    monkeypatch.setenv("SOP_BUILD_CURRENT", "1")
    monkeypatch.setenv("SOP_CODE_BINDING_SHA256", "a" * 64)
    with pytest.raises(basics.sim_lane.LaneError, match="production input changed"):
        basics.candidate(c.args)
    c.build.assert_not_called()
    assert c.receipt.read_text() == "explicit receipt"


def test_missing_explicit_receipt_never_builds(candidate):
    c = candidate
    c.args.receipt, c.args.app = c.receipt, Path(c.built["app_path"])
    with pytest.raises(ValueError, match="存在的原始"):
        basics.candidate(c.args)
    c.build.assert_not_called()
    c.reuse.assert_not_called()


def test_explicit_app_must_match_verified_receipt(candidate):
    c = candidate
    c.receipt.write_text("explicit receipt")
    c.args.receipt, c.args.app = c.receipt, c.receipt.parent / "Other.app"
    with pytest.raises(ValueError, match="包路径不符"):
        basics.candidate(c.args)
    c.build.assert_not_called()


def test_fresh_build_verification_failure_cannot_reach_install(candidate):
    c = candidate
    c.reuse.side_effect = basics.sim_lane.LaneError("source changed during build")
    with pytest.raises(basics.sim_lane.LaneError, match="source changed during build"):
        basics.candidate(c.args)
    c.build.assert_called_once()


def test_busy_does_not_rebuild_or_replace_receipt(candidate):
    c = candidate
    c.receipt.write_text("keep receipt")
    c.reuse.side_effect = basics.sim_lane.Busy("shared resource busy")
    with pytest.raises(basics.sim_lane.Busy):
        basics.candidate(c.args)
    c.build.assert_not_called()
    assert c.receipt.read_text() == "keep receipt"


@pytest.mark.parametrize("failure,expected", [
    ("catalog_timeout", 75), ("raw_timeout", 75), ("busy", 75),
    ("http_error", 1), ("catalog_nonzero", 1), ("assertion", 1),
])
def test_main_preserves_environment_vs_product_failure(monkeypatch, failure, expected):
    lane = basics.sim_lane
    def simctl(*args, **kwargs):
        if failure == "catalog_timeout":
            raise lane.LaneError("xcrun simctl list devicetypes 超过 120s")
        if failure == "raw_timeout":
            raise subprocess.TimeoutExpired(["xcrun", "simctl", *args], 120)
        raise lane.LaneError("xcrun simctl list devicetypes rc=1: runtime not found")
    def run(args):
        if failure == "busy":
            raise lane.Busy("quiet gate")
        if failure == "http_error":
            raise RuntimeError("HTTP 500")
        if failure == "assertion":
            raise AssertionError("settings assertion")
        lane.simctl("list", "devicetypes")
    monkeypatch.setattr(lane, "simctl", simctl)
    monkeypatch.setattr(basics, "run", run)
    monkeypatch.setattr(sys, "argv", [str(ACCEPT / "product_basics.py")])
    with pytest.MonkeyPatch.context() as mp:
        write = Mock()
        mp.setattr(basics, "write", write)
        assert basics.main() == expected
        write.assert_not_called()
    assert lane.simctl is simctl
