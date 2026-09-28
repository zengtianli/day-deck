"""Exercise measurement safety/evidence using synthetic files and mocked commands.

No Xcode, simulator, measurement process or real idle check is started.
"""
from contextlib import ExitStack, redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/measure-simulator.py"
SPEC = importlib.util.spec_from_file_location("measure_simulator_test_target", SCRIPT)
measurement = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(measurement)
DEVICE = "8A5B8741-2AFB-4DAB-9D37-19932473EBFD"  # simctl returns and lists upper-case UDIDs
BUNDLE = "cyou.tianli.daydeck"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"


class MeasureSimulatorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "Sources/main.swift"
        self.source.parent.mkdir()
        self.source.write_text("// synthetic production input\n")
        (self.root / "project.yaml").write_text(json.dumps({"sop": {"source": ["Sources/*.swift"]}}))
        (self.root / "project.yml").write_text(json.dumps({"name": "DayDeck"}))
        for name in ("measure.py", "probe.py", "build-platforms.sh"):
            (self.root / name).write_text("# inert prerequisite fixture\n")
        self.perf = self.root / "perf/simulator.json"
        self.perf.parent.mkdir()
        self.previous = b'{"retained": "previous valid evidence"}\n'
        self.perf.write_bytes(self.previous)
        self.binary = b"synthetic Release binary"
        self.bundle = self.root / ".dd-iphone/Build/Products/Release-iphonesimulator/DayDeck.app"
        self.installed = self.root / "installed/DayDeck.app"
        for app in (self.bundle, self.installed):
            app.mkdir(parents=True)
            (app / "DayDeck").write_bytes(self.binary)
            (app / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "DayDeck", "CFBundleIdentifier": BUNDLE,
                "CFBundleShortVersionString": "0.1", "CFBundleVersion": "3"}))
        self.steady = (True, "synthetic idle gate")
        self.build_fails = False
        self.bad_idle = False
        self.source_changes = False
        sop = types.ModuleType("app_sop")
        sop.steady = lambda: self.steady
        sop.app_source_snapshot = lambda app, patterns: {"sha256": self.source_hash()}
        yaml = types.ModuleType("yaml")
        yaml.safe_load = json.loads
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(sys.modules, {"app_sop": sop, "yaml": yaml}))
        self.stack.enter_context(patch.object(measurement, "ROOT", self.root))
        self.stack.enter_context(patch.object(measurement, "MEASURE", self.root / "measure.py"))
        self.stack.enter_context(patch.object(measurement, "PROBE", self.root / "probe.py"))
        self.commands = self.stack.enter_context(patch.object(measurement, "command", side_effect=self.fake_command))
        self.stack.enter_context(patch.object(measurement.subprocess, "run", side_effect=AssertionError("Real external command forbidden")))
        self.sleep = self.stack.enter_context(patch.object(measurement.time, "sleep"))
        self.stack.enter_context(patch.object(measurement, "load_module", return_value=types.SimpleNamespace(
            device=lambda: "Synthetic Mac host", size_of=lambda path: 12345)))
        self.stack.enter_context(patch.object(measurement, "probe_functions", return_value=self.fake_probe))
        self.stack.enter_context(patch.object(sys, "path", list(sys.path)))

    def source_hash(self):
        return hashlib.sha256(self.source.read_bytes()).hexdigest()

    def files(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}

    def invoke(self, argument):
        with patch.object(sys, "argv", [str(SCRIPT), argument]), redirect_stdout(io.StringIO()):
            return measurement.main()

    def fake_probe(self, bundle, out):
        self.assertEqual(bundle, BUNDLE)
        (out / "launch-log-1.ndjson").write_text('{"synthetic_launch": true}\n')
        return {"runs": 5, "ready_median_ms": 125.0, "launch_complete_median_ms": 180.0,
                "method": "Synthetic test probe; not a real measurement"}

    def fake_command(self, args, **kwargs):
        output, status = "", 0
        if args[:4] == ["xcrun", "simctl", "list", "runtimes"]:
            output = json.dumps({"runtimes": [{"identifier": RUNTIME, "version": "27.0", "isAvailable": True}]})
        elif args[:4] == ["xcrun", "simctl", "list", "devicetypes"]:
            output = json.dumps({"devicetypes": [{"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", "name": "iPhone 17 Pro"}]})
        elif args[:2] == ["bash", "build-platforms.sh"]:
            status = 2 if self.build_fails else 0
        elif args[:3] == ["xcrun", "simctl", "create"]:
            output = DEVICE
        elif args[:4] == ["xcrun", "simctl", "list", "devices"]:
            output = json.dumps({"devices": {RUNTIME: [{"udid": DEVICE, "state": "Booted", "name": "Synthetic dedicated device"}]}})
        elif args[:3] == ["xcrun", "simctl", "get_app_container"]:
            output = str(self.installed)
        elif args[0] == "ditto":
            Path(args[-1]).write_bytes(b"synthetic zip archive")
        elif args[:3] == ["xcrun", "simctl", "launch"]:
            output = BUNDLE + ": 12345"
        elif args[:2] == [sys.executable, str(self.root / "measure.py")]:
            if self.source_changes:
                self.source.write_text("// changed during sampling\n")
            output = json.dumps({"idle": {"footprint_mb": 12.5, "cpu_pct": -1 if self.bad_idle else 0.01}})
        elif args[0] == "ps":
            output = str(self.installed / "DayDeck")
        elif args[:2] == ["git", "rev-parse"]:
            output = "synthetic-git-head"
        elif args[:2] == ["xcrun", "simctl"] and args[2] in ("boot", "bootstatus", "install", "terminate", "shutdown", "delete"):
            self.assertEqual(args[3], DEVICE, "Must operate only on this invocation's device")
        else:
            raise AssertionError(f"Unexpected external command: {args}")
        return subprocess.CompletedProcess(args, status, output, "")

    def test_busy_gate_exits_before_any_command_or_evidence_write(self):
        self.steady = (False, "synthetic busy machine")
        before = self.files()
        with self.assertRaises(SystemExit) as stopped:
            self.invoke("--run")
        self.assertEqual(stopped.exception.code, 75)
        self.commands.assert_not_called()
        self.sleep.assert_not_called()
        self.assertEqual(self.files(), before)
        self.assertFalse((self.root / "build").exists())

    def test_check_is_read_only_even_when_gate_passes(self):
        before = self.files()
        self.invoke("--check")
        self.commands.assert_not_called()
        self.sleep.assert_not_called()
        self.assertEqual(self.files(), before)
        self.assertFalse((self.root / "build").exists())

    def test_success_binds_summary_to_raw_source_and_installed_binary(self):
        expected_source = self.source_hash()
        self.invoke("--run")
        summary = json.loads(self.perf.read_text())
        receipt = summary["runtime_measurement"]
        raw_path = self.root / receipt["evidence"]
        self.assertEqual(receipt["evidence_sha256"], hashlib.sha256(raw_path.read_bytes()).hexdigest())
        raw = json.loads(raw_path.read_text())
        expected_binary = hashlib.sha256(self.binary).hexdigest()
        self.assertEqual(raw["binary_sha256"], expected_binary)
        self.assertEqual(raw["installed_binary_sha256"], expected_binary)
        self.assertEqual(raw["input_sha256"], expected_source)
        self.assertEqual(summary["build"]["input_sha256"], expected_source)
        self.assertEqual(summary["build"]["binary_sha256"], expected_binary)
        self.assertEqual(summary["version"], "0.1 (3)")
        self.assertEqual(receipt["environment"], "simulator")
        self.assertEqual(raw["launch_logs"]["launch-log-1.ndjson"], '{"synthetic_launch": true}\n')
        for speed in summary["speed_gui"]:
            self.assertEqual(speed["evidence_sha256"], receipt["evidence_sha256"])
        operations = [call.args[0] for call in self.commands.call_args_list]
        self.assertEqual(operations[-1], ["xcrun", "simctl", "delete", DEVICE])

    def test_failed_build_preserves_previous_evidence_without_creating_device(self):
        self.build_fails = True
        with self.assertRaises(RuntimeError):
            self.invoke("--run")
        self.assertEqual(self.perf.read_bytes(), self.previous)
        self.assertFalse((self.root / "perf/raw").exists())
        self.assertFalse(any(call.args[0][:3] == ["xcrun", "simctl", "create"] for call in self.commands.call_args_list))

    def test_invalid_sample_preserves_previous_evidence_and_cleans_own_device(self):
        self.bad_idle = True
        with self.assertRaises(RuntimeError):
            self.invoke("--run")
        self.assertEqual(self.perf.read_bytes(), self.previous)
        self.assertFalse((self.root / "perf/raw").exists())
        self.assertEqual(self.commands.call_args.args[0], ["xcrun", "simctl", "delete", DEVICE])

    def test_source_change_during_sampling_cannot_publish_passed_evidence(self):
        self.source_changes = True
        with self.assertRaises(RuntimeError):
            self.invoke("--run")
        self.assertEqual(self.perf.read_bytes(), self.previous)
        self.assertFalse((self.root / "perf/raw").exists())


if __name__ == "__main__":
    unittest.main()
