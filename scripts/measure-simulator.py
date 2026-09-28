#!/usr/bin/env python3
"""Guarded Notihub simulator measurement. --check is read-only; --run builds and measures a fresh simulator."""
import argparse
import ast
import datetime
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import plistlib
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
CHAPTER = Path.home() / "Apps/chapter/engine"
MEASURE = Path.home() / "Apps/.claude/skills/app-lightweight/scripts/measure.py"
PROBE = Path.home() / "Library/Logs/app-sop/ios-simulator-20260927b/sim_perf.py"
ENV = {k: v for k, v in os.environ.items() if k in ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "SHELL", "LANG", "DEVELOPER_DIR")}
SCOPE = "Simulator App process only; excludes CoreSimulator, Simulator GUI, system services and inactive extensions"


def command(args, check=True, timeout=120, cwd=None):
    # Own a process group so a timed-out build cannot leave bash/xcodebuild
    # descendants working after the runner reports failure.
    process = subprocess.Popen(args, cwd=cwd or ROOT, env=ENV, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()
        raise
    result = subprocess.CompletedProcess(args, process.returncode, stdout, stderr)
    if check:
        result.check_returncode()
    return result


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def clock():
    return datetime.datetime.now().astimezone().isoformat()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def gate(sop):
    passed, reason = sop.steady()
    print(json.dumps({"steady": passed, "reason": reason, "checked_at": clock()}, ensure_ascii=False), flush=True)
    if not passed:
        raise SystemExit(75)


def probe_functions(device):
    # Reuse only the existing pure probe functions. Do not import its obsolete
    # module-level UDID file, output directory or old app_sop import path.
    tree = ast.parse(PROBE.read_text())
    names = {"log_ts", "launch_once", "probe"}
    nodes = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
    if {node.name for node in nodes} != names:
        raise RuntimeError("Existing simulator launch probe interface changed")
    namespace = dict(datetime=datetime, re=re, statistics=statistics, time=time,
                     json=json, cmd=command, DEVICE=device, RUNS=5)
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(PROBE), "exec"), namespace)
    return namespace["probe"]


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".measurement-", delete=False) as file:
        temporary = Path(file.name)
        try:
            json.dump(value, file, ensure_ascii=False, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true", help="read-only idle gate and dependency check; busy exits 75")
    action.add_argument("--run", action="store_true", help="build Release, install only on a newly created simulator, measure, then remove it")
    parser.add_argument("--runtime", help="available iOS simulator runtime identifier; default newest available")
    parser.add_argument("--device-type", default="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro")
    args = parser.parse_args()
    sys.path.insert(0, str(CHAPTER))
    import app_sop
    import yaml
    gate(app_sop)  # No build, simulator mutation, directory creation or perf write before this gate.
    for path in (MEASURE, PROBE, ROOT / "build-platforms.sh"):
        if not path.is_file():
            raise RuntimeError(f"Required existing entry is unavailable: {path}")
    if args.check:
        print(json.dumps({"ready": True, "action": "check", "measured": False}))
        return

    spec = yaml.safe_load((ROOT / "project.yaml").read_text())
    project = yaml.safe_load((ROOT / "project.yml").read_text())
    app = {"repo": ROOT, "sop": spec["sop"]}
    patterns = app["sop"].get("source") or app["sop"].get("ui")
    if not patterns:
        raise RuntimeError("No sop.source inputs; cannot bind measurement")
    snapshot = lambda: app_sop.app_source_snapshot(app, patterns)["sha256"]
    source_sha = snapshot()
    perf = ROOT / "perf/simulator.json"
    previous = perf.read_bytes() if perf.exists() else None
    runtime_rows = json.loads(command(["xcrun", "simctl", "list", "runtimes", "--json"]).stdout)["runtimes"]
    candidates = [r for r in runtime_rows if r.get("isAvailable") and ".iOS-" in r["identifier"]
                  and (not args.runtime or r["identifier"] == args.runtime)]
    if not candidates:
        raise RuntimeError("Requested iOS simulator runtime is unavailable")
    runtime = max(candidates, key=lambda r: tuple(int(n) for n in re.findall(r"\d+", r["version"])))
    types = json.loads(command(["xcrun", "simctl", "list", "devicetypes", "--json"]).stdout)["devicetypes"]
    device_type = next((t for t in types if t["identifier"] == args.device_type), None)
    if not device_type:
        raise RuntimeError("Requested simulator device type is unavailable")
    measure = load_module("notihub_measure", MEASURE)
    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="simulator-perf-", dir=ROOT / "build") as temporary:
        out = Path(temporary)
        build_started = time.monotonic()
        result = command(["bash", "build-platforms.sh", "--only", "iphone", "--release"], check=False, timeout=900)
        (out / "build.log").write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError("Release build failed: " + (result.stdout + result.stderr)[-2500:])
        if snapshot() != source_sha:
            raise RuntimeError("Source changed during build; no measurement recorded")
        bundle_path = ROOT / ".dd-iphone/Build/Products/Release-iphonesimulator" / (project["name"] + ".app")
        info = plistlib.loads((bundle_path / "Info.plist").read_bytes())
        executable, bundle = info["CFBundleExecutable"], info["CFBundleIdentifier"]
        version = f"{info['CFBundleShortVersionString']} ({info['CFBundleVersion']})"
        binary_sha = sha(bundle_path / executable)
        receipt = {"configuration": "Release", "seconds": round(time.monotonic() - build_started, 1),
                   "source_sha256": source_sha, "source_unchanged": True, "built_from": "working tree",
                   "command": "bash build-platforms.sh --only iphone --release"}
        gate(app_sop)  # Never sample immediately into a busy post-build window.
        device = None
        record = None
        try:
            created = command(["xcrun", "simctl", "create", "Notihub Perf " + str(uuid.uuid4()),
                               device_type["identifier"], runtime["identifier"]]).stdout.strip()
            device = str(uuid.UUID(created))  # Only a validated owned UUID enters cleanup.
            command(["xcrun", "simctl", "boot", device])
            command(["xcrun", "simctl", "bootstatus", device, "-b"], timeout=180)
            actual_rows = json.loads(command(["xcrun", "simctl", "list", "devices", "--json"]).stdout)["devices"]
            actual = next(d for d in actual_rows.get(runtime["identifier"], []) if d["udid"] == device)
            if actual["state"] != "Booted":
                raise RuntimeError("Dedicated simulator is not booted")
            command(["xcrun", "simctl", "install", device, str(bundle_path)])
            installed = Path(command(["xcrun", "simctl", "get_app_container", device, bundle, "app"]).stdout.strip())
            installed_sha = sha(installed / executable)
            if installed_sha != binary_sha:
                raise RuntimeError("Installed simulator executable differs from built Release")
            archive = out / "DayDeck.app.zip"
            command(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(bundle_path), str(archive)])
            gate(app_sop)
            measured_at = clock()
            launch = probe_functions(device)(bundle, out)
            if launch["runs"] != 5 or not launch.get("ready_median_ms") or not launch.get("launch_complete_median_ms"):
                raise RuntimeError("Launch probe did not produce all five ready/completed samples")
            command(["xcrun", "simctl", "terminate", device, bundle], check=False)
            launched = command(["xcrun", "simctl", "launch", device, bundle]).stdout
            pid = int(re.search(r":\s*(\d+)\s*$", launched).group(1))
            time.sleep(45)
            gate(app_sop)
            idle = json.loads(command([sys.executable, str(MEASURE), "idle", str(pid), "--seconds", "60"], timeout=100).stdout)["idle"]
            if not command(["ps", "-p", str(pid), "-o", "comm="]).stdout.strip().endswith("/" + executable):
                raise RuntimeError("Measured PID no longer belongs to the App")
            for key in ("footprint_mb", "cpu_pct"):
                if not isinstance(idle.get(key), (int, float)) or not math.isfinite(idle[key]) or idle[key] < 0:
                    raise RuntimeError("Invalid idle sample: " + key)
            if not idle["footprint_mb"]:
                raise RuntimeError("Missing footprint")
            gate(app_sop)
            if snapshot() != source_sha or sha(bundle_path / executable) != binary_sha:
                raise RuntimeError("Source/build changed during sampling")
            record = {"schema_version": 1, "app_id": "day-deck-ios", "environment": "simulator", "mode": "full",
                      "measured_at": measured_at, "completed_at": clock(), "configuration": "Release", "version": version,
                      "bundle_id": bundle, "binary_sha256": binary_sha, "installed_binary_sha256": installed_sha,
                      "input_sha256": source_sha, "build_receipt": receipt, "git_head": command(["git", "rev-parse", "HEAD"]).stdout.strip(),
                      "simulator_device": device_type["name"], "simulator_runtime": runtime,
                      "simulator_os": "iOS " + runtime["version"], "simulator_readback": actual, "host": measure.device(),
                      "measurement_tool_sha256": sha(MEASURE), "probe_sha256": sha(PROBE), "adapter_sha256": sha(__file__),
                      "scope": SCOPE, "source_unchanged_during_measurement": True, "launch": launch,
                      "launch_logs": {p.name: p.read_text() for p in out.glob("launch-log-*.ndjson")},
                      "idle": {**idle, "settle_s": 45, "footprint_unit": "MiB", "scope": SCOPE},
                      "size": {"download_bytes": archive.stat().st_size, "installed_bytes": measure.size_of(installed),
                               "kind": "Local simulator .app ZIP; not an App Store IPA or device slice"}}
        finally:
            if device:
                try:
                    command(["xcrun", "simctl", "shutdown", device], check=False)
                finally:
                    command(["xcrun", "simctl", "delete", device])
        # Publish only after own simulator cleanup; never overwrite a concurrent measurement.
        if (perf.read_bytes() if perf.exists() else None) != previous or snapshot() != source_sha:
            raise RuntimeError("Performance evidence/source changed concurrently; no writeback")
        raw_relative = "perf/raw/simulator-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8] + ".json"
        raw_path = ROOT / raw_relative
        atomic_json(raw_path, record)
        raw_sha = sha(raw_path)
        method = launch["method"] + " Median of 5 complete samples; original logs attached to raw evidence."
        summary = {"schema_version": 1, "product": "day-deck", "platform": "ios", "version": version,
                   "configuration": "Release", "measured_at": measured_at, "device": device_type["name"] + " / " + record["simulator_os"] + " Simulator / " + record["host"],
                   "input_sha256": source_sha, "git_head": record["git_head"], "data": "Fresh dedicated simulator container; first-run data; no production data imported",
                   "size": record["size"], "idle": record["idle"], "scope": SCOPE,
                   "runtime_measurement": {"environment": "simulator", "device": device_type["name"], "os": record["simulator_os"],
                                           "version": version, "evidence": raw_relative, "evidence_sha256": raw_sha},
                   "build": {"configuration": "Release", "binary_sha256": binary_sha, "input_sha256": source_sha,
                             "built_from": "working tree", "actual_build": True},
                   "speed_gui": [{"key": key, "label": label, "median_ms": launch[value], "runs": 5, "headline": headline,
                                  "method": method, "evidence": raw_relative, "evidence_sha256": raw_sha}
                                 for key, label, value, headline in [("first_screen_ready", "模拟器冷启动到首屏就绪", "ready_median_ms", True),
                                                                  ("launch_complete", "模拟器冷启动到系统判定启动完成", "launch_complete_median_ms", False)]],
                   "limitations": "模拟器应用进程；内存 footprint_mb 为 MiB；排除 Simulator/CoreSimulator 开销；ZIP 非 App Store 下载包；未测后台及任务峰值。"}
        atomic_json(perf, summary)
        print(json.dumps({"measured": True, "evidence": str(perf), "raw": raw_relative, "binary_sha256": binary_sha}, ensure_ascii=False))


if __name__ == "__main__":
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt("Termination requested")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print(f"Measurement stopped without a passed record: {error}", file=sys.stderr)
        raise SystemExit(1)
