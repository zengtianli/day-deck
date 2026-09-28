"""Safety checks only: never invoke xcrun or create a simulator."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("capture_demo", Path(__file__).resolve().parents[2] / "scripts/capture-demo.py")
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


class CaptureDemoTests(unittest.TestCase):
    def test_shared_picker_can_select_unique_iphone_name(self):
        first, second = capture.simulator_name(), capture.simulator_name()
        self.assertIn("iPhone", first)
        self.assertNotEqual(first, second)

    @patch.object(capture.subprocess, "run")
    def test_shutdown_timeout_still_deletes_only_owned_uuid(self, run):
        device = "8a5b8741-2afb-4dab-9d37-19932473ebfd"
        run.side_effect = [subprocess.TimeoutExpired("shutdown", 30), subprocess.CompletedProcess([], 0)]
        capture.cleanup_device(device)
        self.assertEqual([call.args[0] for call in run.call_args_list], [
            ["xcrun", "simctl", "shutdown", device], ["xcrun", "simctl", "delete", device]])

    @patch.object(capture.subprocess, "Popen")
    def test_shared_build_stays_headless_and_disables_extra_screenshots(self, popen):
        popen.return_value.wait.return_value = 0
        popen.return_value.poll.return_value = 0
        capture.build_demo({}, "Notihub-public-iPhone-test", None)
        args, kwargs = popen.call_args
        self.assertEqual(args[0], ["bash", "sim-run.sh", "--no-shot", "--shutdown"])
        self.assertTrue(kwargs["start_new_session"])
        self.assertEqual(kwargs["env"]["SIM_LAUNCH_ARGS"], "-demo 1 -tab 0")

    @patch.object(capture.os, "killpg")
    @patch.object(capture.subprocess, "Popen")
    def test_build_timeout_stops_only_its_process_group(self, popen, killpg):
        process = popen.return_value
        process.pid = 23456
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired("build", 600), 0]
        with self.assertRaises(subprocess.TimeoutExpired):
            capture.build_demo({}, "Notihub-public-iPhone-test", None)
        killpg.assert_called_once_with(23456, capture.signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()
