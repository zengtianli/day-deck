import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "media"))
import capture_admission as admission


class CaptureAdmissionTests(unittest.TestCase):
    def test_original_lane_replaces_load_average_only_gate(self):
        with patch.object(admission.sim_lane, "machine_busy", return_value="") as cpu, \
                patch.object(admission.sim_lane, "memory_tight", return_value=""), \
                patch.object(admission.sim_lane, "heavy_builds", return_value=[]), \
                patch.object(admission.app_sop, "steady", side_effect=AssertionError("legacy load gate")):
            self.assertTrue(admission.check(True)[0])
        cpu.assert_called_once()

    def test_machine_contention_is_preserved(self):
        with patch.object(admission.sim_lane, "machine_busy", return_value="CPU busy"), \
                patch.object(admission.sim_lane, "memory_tight", return_value="memory tight"), \
                patch.object(admission.sim_lane, "heavy_builds", return_value=["other-build"]):
            okay, reason = admission.check(True)
        self.assertFalse(okay)
        self.assertIn("CPU busy", reason)
        self.assertIn("memory tight", reason)
        self.assertIn("构建", reason)


if __name__ == "__main__":
    unittest.main()
