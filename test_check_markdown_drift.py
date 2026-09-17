"""Isolated counterexamples for check-markdown-drift.sh (run: python3 -m unittest test_check_markdown_drift)."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

CHECK = Path(__file__).resolve().parent / "check-markdown-drift.sh"
BODY = b"import SwiftUI\nstruct Renderer {}\n"


class MarkdownCopyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source.swift"
        self.target = self.root / "consumer.swift"
        self.source.write_bytes(BODY)
        self.header = b"// consumer ownership from day-deck\n\n"
        self.target.write_bytes(self.header + BODY)

    def run_check(self, targets=None, sync=False):
        argv = ["/bin/bash", str(CHECK), "--source", str(self.source), "--targets"]
        argv += [str(p) for p in ([self.target] if targets is None else targets)]
        if sync:
            argv.append("--sync")
        result = subprocess.run(argv, capture_output=True, text=True)
        return result, json.loads(result.stdout)

    def test_header_difference_allowed_and_check_has_no_writes(self):
        before = self.target.read_bytes()
        result, report = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report["consumers"], 1)
        self.assertEqual(self.target.read_bytes(), before)
        self.assertEqual(len(list(self.root.iterdir())), 2)

    def test_changed_body_is_failure(self):
        self.target.write_bytes(self.header + BODY.replace(b"Renderer", b"Changed"))
        result, report = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(report["entries"][0]["result"], "drifted")

    def test_missing_source_target_and_zero_consumers_fail(self):
        self.assertEqual(self.run_check([])[0].returncode, 2)
        self.target.unlink()
        self.assertEqual(self.run_check()[0].returncode, 2)
        self.target.write_bytes(self.header + BODY)
        self.source.unlink()
        self.assertEqual(self.run_check()[0].returncode, 2)

    def test_code_before_import_cannot_be_hidden_as_a_header(self):
        self.target.write_bytes(b"let alteredBehavior = true\n" + BODY)
        result, report = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertIn("Non-comment", report["error"])

    def test_sync_preserves_header_and_before_image(self):
        before = self.header + BODY.replace(b"Renderer", b"Old")
        self.target.write_bytes(before)
        result, report = self.run_check(sync=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.read_bytes(), self.header + BODY)
        self.assertEqual(Path(report["entries"][0]["backup"]).read_bytes(), before)
        self.assertEqual(self.run_check()[0].returncode, 0)

    def test_missing_consumer_aborts_sync_before_other_copy(self):
        before = self.header + BODY.replace(b"Renderer", b"Old")
        self.target.write_bytes(before)
        result, _ = self.run_check([self.target, self.root / "missing.swift"], sync=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.target.read_bytes(), before)

    def test_same_source_or_duplicate_consumer_is_not_coverage(self):
        self.assertEqual(self.run_check([self.source])[0].returncode, 2)
        self.assertEqual(self.run_check([self.target, self.target])[0].returncode, 2)


if __name__ == "__main__":
    unittest.main()
