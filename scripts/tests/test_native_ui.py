"""Native review launcher regressions; no simulator, build or network access."""
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
from unittest.mock import patch

import pytest


ACCEPT = Path(__file__).resolve().parents[1] / "accept"
SPEC = importlib.util.spec_from_file_location("native_ui_accept", ACCEPT / "native_ui.py")
native = importlib.util.module_from_spec(SPEC)
with patch.object(sys, "path", [str(ACCEPT), *sys.path]):
    SPEC.loader.exec_module(native)

BUNDLE = "cyou.tianli.daydeck"


def test_launcher_returns_while_descendant_holds_output_open(tmp_path):
    """Real OS processes reproduce PIPE EOF waiting without involving CoreSimulator."""
    child_file = tmp_path / "child.pid"
    launcher = [sys.executable, "-c", "\n".join([
        "import pathlib, subprocess, sys",
        "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])",
        "pathlib.Path(sys.argv[1]).write_text(str(child.pid))",
        f"print('{BUNDLE}: ' + str(child.pid), flush=True)",
    ]), str(child_file)]
    real_run = subprocess.run
    def reap():
        if child_file.exists():
            pid = int(child_file.read_text())
            os.kill(pid, signal.SIGKILL)
            child_file.unlink()

    try:
        # The old capture_output=True path times out despite the launcher exiting.
        with pytest.raises(subprocess.TimeoutExpired):
            real_run(launcher, capture_output=True, text=True, timeout=1)
        reap()

        def run_fake_launcher(command, **kwargs):
            assert command == ["xcrun", "simctl", "launch", "--stdout=/dev/null",
                               "--stderr=/dev/null", "owned-uuid", BUNDLE, "--review-self-test"]
            assert kwargs["env"]["DEVELOPER_DIR"] == "/test/Xcode/Contents/Developer"
            assert kwargs["timeout"] == 60
            assert kwargs["stdin"] == kwargs["stderr"] == subprocess.DEVNULL
            # Keep the regression fast even if PIPE capture is reintroduced.
            kwargs["timeout"] = 1
            return real_run(launcher, **kwargs)

        with patch.object(native.sim_lane, "developer_dir", return_value="/test/Xcode/Contents/Developer"), \
                patch.object(native.subprocess, "run", side_effect=run_fake_launcher):
            pid = native.launch_review("owned-uuid", BUNDLE)
        assert pid == int(child_file.read_text())
        os.kill(pid, 0)  # The child still holds the descriptors; no EOF was needed.
    finally:
        reap()


@pytest.mark.parametrize("output", ["", f"{BUNDLE}: 0", f"other.bundle: 123", f"{BUNDLE}: 123\nextra"])
def test_invalid_launch_receipt_is_rejected(output):
    def run(command, **kwargs):
        kwargs["stdout"].write(output)
        return subprocess.CompletedProcess(command, 0)

    with patch.object(native.sim_lane, "developer_dir", return_value="/test/Xcode"), \
            patch.object(native.subprocess, "run", side_effect=run):
        with pytest.raises(native.AcceptanceError, match="实际进程 PID"):
            native.launch_review("owned-uuid", BUNDLE)


def test_nonzero_launch_cannot_become_a_pass_even_with_pid():
    def run(command, **kwargs):
        kwargs["stdout"].write(f"{BUNDLE}: 123\n")
        return subprocess.CompletedProcess(command, 3)

    with patch.object(native.sim_lane, "developer_dir", return_value="/test/Xcode"), \
            patch.object(native.subprocess, "run", side_effect=run):
        with pytest.raises(native.AcceptanceError, match="退出码 3"):
            native.launch_review("owned-uuid", BUNDLE)


def test_real_launcher_timeout_still_fails_without_leaking_output():
    timeout = subprocess.TimeoutExpired(["xcrun", "simctl", "launch"], 60,
                                        output="private output", stderr="private stderr")
    with patch.object(native.sim_lane, "developer_dir", return_value="/test/Xcode"), \
            patch.object(native.subprocess, "run", side_effect=timeout):
        with pytest.raises(native.AcceptanceError, match="超过 60s") as caught:
            native.launch_review("owned-uuid", BUNDLE)
    assert "private" not in str(caught.value)


def test_shared_busy_is_not_reclassified_as_product_failure():
    with patch.object(native.sim_lane, "developer_dir", side_effect=native.sim_lane.Busy("shared busy")):
        with pytest.raises(native.sim_lane.Busy):
            native.launch_review("owned-uuid", BUNDLE)
