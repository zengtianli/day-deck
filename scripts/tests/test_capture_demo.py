"""Safety checks only: never invoke xcrun or create a simulator."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import Mock, patch

SPEC = importlib.util.spec_from_file_location("capture_demo", Path(__file__).resolve().parents[2] / "scripts/capture-demo.py")
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


class CaptureDemoTests(unittest.TestCase):
    @patch.object(capture.importlib, "import_module")
    def test_failed_admission_does_not_create_or_build_a_simulator(self, import_module):
        sop = Mock()
        sop.steady.return_value = (False, "load busy")
        import_module.return_value = sop
        with patch.object(capture, "build_demo") as build, patch.object(capture, "run") as run, \
                patch.object(capture, "recording_gate", return_value=(False, "shared gate busy")) as gate:
            self.assertEqual(capture.main(["--check", "--in-use"]), 75)
        gate.assert_called_once_with(True)
        sop.steady.assert_not_called()
        import_module.assert_called_once_with("app_sop")
        build.assert_not_called()
        run.assert_not_called()

    def test_shared_picker_can_select_unique_iphone_name(self):
        first, second = capture.simulator_name(), capture.simulator_name()
        self.assertIn("iPhone", first)
        self.assertNotEqual(first, second)

    def test_named_device_uses_the_name_keyword_not_a_fabricated_device_type(self):
        lane = Mock()
        lane.ensure_device.return_value = {"created": True, "udid": "owned"}
        capture.recording_device(lane)
        args, kwargs = lane.ensure_device.call_args
        self.assertEqual(args, ("iphone",))
        self.assertTrue(kwargs["name"].startswith("Notihub-public-iPhone-"))

    def test_existing_device_is_refused_before_cleanup_can_own_it(self):
        lane = Mock()
        lane.ensure_device.return_value = {"created": False, "udid": "someone-elses-device"}
        with self.assertRaisesRegex(RuntimeError, "existing simulator"):
            capture.recording_device(lane)

    @patch.object(capture.subprocess, "run")
    def test_shutdown_timeout_still_deletes_only_owned_uuid(self, run):
        device = "8a5b8741-2afb-4dab-9d37-19932473ebfd"
        run.side_effect = [subprocess.TimeoutExpired("shutdown", 30), subprocess.CompletedProcess([], 0)]
        capture.cleanup_device(device)
        self.assertEqual([call.args[0] for call in run.call_args_list], [
            ["xcrun", "simctl", "shutdown", device], ["xcrun", "simctl", "delete", device]])

    def test_recording_uses_original_builder_instead_of_starting_an_unlocked_shell(self):
        lane = Mock()
        work = Path("/private/tmp/capture-test")
        capture.build_demo(lane, work)
        lane.build.assert_called_once_with(capture.ROOT, "DayDeck", "iphone", "Debug", work / "build")
        lane.reuse_build.assert_not_called()

    def test_invalid_reuse_cannot_fall_back_to_an_unrequested_build(self):
        lane = Mock()
        lane.reuse_build.side_effect = RuntimeError("source binding changed")
        with self.assertRaisesRegex(RuntimeError, "source binding changed"):
            capture.build_demo(lane, Path("/private/tmp/capture-test"), Path("receipt.json"))
        lane.build.assert_not_called()

    @patch.object(capture.subprocess, "run")
    def test_session_cleanup_does_not_shutdown_another_device(self, run):
        device = "8a5b8741-2afb-4dab-9d37-19932473ebfd"
        run.return_value = subprocess.CompletedProcess([], 0)
        capture.cleanup_device(device, shutdown=False)
        run.assert_called_once_with(["xcrun", "simctl", "delete", device], capture_output=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
