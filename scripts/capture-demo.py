#!/usr/bin/env python3
"""Record four real, read-only simulator clips; no desktop UI or synthetic input.

Run with the shared Python environment. A failed idle gate exits 75 before build,
installation, simulator creation or changes to existing footage. --check only
checks prerequisites and the gate. Chapter writes playback evidence separately.
"""
import argparse
import contextlib
import hashlib
import importlib
import json
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "cyou.tianli.daydeck"
SECTIONS = [("今天：四组待办", "0", ""), ("通知：摘要与时间线", "1", ""),
            ("搜索：当天房东通知", "1", "房东"), ("随手记：云端记录", "2", "")]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True,
                          timeout=kwargs.pop("timeout", 60), **kwargs)


def clock(seconds):
    milliseconds = round(seconds * 1000)
    return f"{milliseconds // 3600000:02d}:{milliseconds // 60000 % 60:02d}:{milliseconds // 1000 % 60:02d}.{milliseconds % 1000:03d}"


def simulator_name():
    # The shared picker filters by family in the name before matching SIM_NAME.
    return "Notihub-public-iPhone-" + uuid.uuid4().hex[:12]


def cleanup_device(device, shutdown=True):
    for operation in (("shutdown", "delete") if shutdown else ("delete",)):
        try:
            result = subprocess.run(["xcrun", "simctl", operation, device], capture_output=True, timeout=30)
            if result.returncode:
                print(f"Cleanup {operation} returned {result.returncode} for owned simulator {device}", file=sys.stderr)
        except (OSError, subprocess.TimeoutExpired) as error:
            # A shutdown timeout must not skip deletion or replace the original error.
            print(f"Cleanup {operation} failed for owned simulator {device}: {error}", file=sys.stderr)


def build_demo(lane, work, receipt=None):
    if receipt is not None:
        return lane.reuse_build(receipt, "day-deck-ios", ROOT, "iphone", "DayDeck")
    # The shared builder stages outside the repository and owns parallel build admission.
    return lane.build(ROOT, "DayDeck", "iphone", "Debug", work / "build")


def interrupted(signum, frame):
    raise KeyboardInterrupt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check prerequisites and idle gate only")
    parser.add_argument("--reuse-build", type=Path, help="Strictly verify and reuse the original sim_lane build receipt")
    parser.add_argument("--in-use", action="store_true", help="Headless recording while the owner is active; retain load and simulator locks")
    args = parser.parse_args(argv)
    sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
    sop = importlib.import_module("app_sop")
    okay, reason = sop.steady(user_away=not args.in_use, allow_owner_now=False)
    if not okay:
        print(f"BLOCKED: {reason}; no build, installation or recording performed", flush=True)
        return 75
    for executable in ("xcrun", "ffmpeg", "ffprobe"):
        if not shutil.which(executable):
            raise RuntimeError(f"Missing prerequisite: {executable}")
    if args.check:
        print(f"READY: {reason}; no simulator started")
        return 0
    sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
    lane = importlib.import_module("sim_lane")
    product = sop.load_apps("day-deck-ios")[0]
    source = sop.lane_inputs(product, "iphone")

    # sim_lane owns the sanitized build environment and build-slot lifecycle.
    device = None
    recorder = None
    staging = None
    native = contextlib.ExitStack()
    try:
        staging = lane.make_temp("notihub-demo.")
        built = build_demo(lane, staging, args.reuse_build)
        name = simulator_name()
        dev = lane.ensure_device("iphone", name, None)
        device = str(uuid.UUID(dev["udid"]))
        session = native.enter_context(lane.Session("iphone", device, label="notihub-public-video",
                                                   keep_booted=False, lock_wait=0, load_wait=0))
        session.install(Path(built["app_path"]))
        print("Dedicated simulator prepared under the original lane lock", flush=True)
        installed_app = Path(run("xcrun", "simctl", "get_app_container", device, BUNDLE, "app").stdout.strip())
        info = plistlib.loads((installed_app / "Info.plist").read_bytes())
        executable = installed_app / info["CFBundleExecutable"]
        # Xcode Debug builds move app code into <name>.debug.dylib; the main executable is a stub.
        code = [executable, *installed_app.glob(info["CFBundleExecutable"] + ".debug.dylib")]
        if not any("交季度报销单".encode() in path.read_bytes() for path in code):
            raise RuntimeError("Installed executable lacks the DEBUG synthetic-data marker; refusing public recording (checked: "
                               + ", ".join(f"{path.name} {path.stat().st_size} B" for path in code) + ")")
        clips = []
        for index, (title, tab, search) in enumerate(SECTIONS, 1):
            print(f"Recording {index}/4: {title}", flush=True)
            session.terminate(BUNDLE)
            baseline, _ = session.baseline()
            launched = session.launch(BUNDLE, ["-demo", "1", "-tab", tab, "-search", search],
                                      "auto", 90, baseline, str(executable))
            verdict = launched.get("verdict") or {}
            if (launched.get("errors") or not launched.get("ready_signal")
                    or not verdict.get("non_blank") or not verdict.get("changed_from_baseline")):
                raise RuntimeError(f"Real App did not reach a rendered page: {launched.get('errors')}")
            time.sleep(2)  # Separate setup from the recorded, fully visible page.
            clip = staging / f"{index:02d}.mp4"
            with (staging / f"{index:02d}-capture.log").open("w") as log:
                recorder = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(clip)],
                                            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                time.sleep(6)
                if recorder.poll() is not None:
                    raise RuntimeError(f"Recorder exited before clip {index} finished; inspect {log.name}")
                recorder.send_signal(signal.SIGINT)
                status = recorder.wait(timeout=20)
                if status not in (0, -signal.SIGINT, 128 + signal.SIGINT):
                    raise RuntimeError(f"Recorder failed with exit {status}; inspect {log.name}")
                recorder = None
            # recordVideo only writes frames when the screen changes, so a static page yields a
            # near-zero-length file. Hold the last real frame to a fixed 5 s at constant 30 fps.
            steady_clip = staging / f"{index:02d}-cfr.mp4"
            run("ffmpeg", "-v", "error", "-i", str(clip), "-vf", "tpad=stop_mode=clone:stop_duration=6,fps=30",
                "-t", "5", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(steady_clip), timeout=90)
            clip = steady_clip
            duration = float(run("ffprobe", "-v", "error", "-show_entries", "format=duration",
                                 "-of", "default=nw=1:nk=1", str(clip)).stdout)
            if duration < 2:
                raise RuntimeError(f"Clip {index} too short ({duration}s)")
            run("ffmpeg", "-v", "error", "-i", str(clip), "-f", "null", "-", timeout=90)
            clips.append((clip, title, duration))

        native.close()

        concat = staging / "concat.txt"
        concat.write_text("".join(f"file '{clip.name}'\n" for clip, _, _ in clips))
        result = staging / "public-demo.mp4"
        run("ffmpeg", "-v", "error", "-f", "concat", "-safe", "1", "-i", str(concat),
            "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(result), timeout=120)
        run("ffmpeg", "-v", "error", "-i", str(result), "-f", "null", "-", timeout=90)
        subtitles, elapsed = ["WEBVTT\n"], 0.0
        for _, title, duration in clips:
            subtitles.append(f"\n{clock(elapsed)} --> {clock(elapsed + duration)}\n{title}（合成数据，独立只读片段）\n")
            elapsed += duration
        (staging / "public-demo.vtt").write_text("".join(subtitles))
        manifest = {"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                    "environment": "iOS Simulator", "configuration": built["configuration"], "synthetic_data": True,
                    "input_sha256": source["input_sha256"], "source_snapshot": source,
                    "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                    "code_sha256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in code},
                    "reused_build": bool(args.reuse_build), "build_reuse": built.get("reuse"),
                    "capture_method": "one original sim_lane.Session; no Simulator GUI or synthetic input",
                    "coverage": "Four real read-only views, separately launched; no save/login/gesture demonstration",
                    "clips": [{"file": c.name, "title": t, "duration": d} for c, t, d in clips],
                    "visual_review": "pending", "playback_acceptance": "Run Chapter media_playback separately"}
        (staging / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        if sop.lane_inputs(product, "iphone")["input_sha256"] != source["input_sha256"]:
            raise RuntimeError("Source changed during recording; existing footage preserved")
        target = ROOT / "shots"
        target.mkdir(exist_ok=True)
        # Publish files only after every clip and the final video decoded successfully.
        for filename in ("public-demo.mp4", "public-demo.vtt"):
            temporary = target / ("." + filename + ".new")
            shutil.copy2(staging / filename, temporary)
            temporary.replace(target / filename)
        shutil.copy2(staging / "manifest.json", target / "public-demo-recording.json")
        print(f"Recorded {elapsed:.1f}s to shots/public-demo.mp4; review frames, then run Chapter playback acceptance")
        return 0
    except lane.Busy as error:
        print(f"BLOCKED: {error}; existing footage preserved", file=sys.stderr)
        return 75
    finally:
        if recorder and recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
            try:
                recorder.wait(timeout=20)
            except subprocess.TimeoutExpired:
                recorder.kill()
                recorder.wait()
        try:
            native.close()
        finally:
            if device:
                # Session owns shutdown; delete only our uniquely named, fresh device.
                cleanup_device(device, shutdown=False)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupted)
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("CANCELLED: own recording and simulator cleanup requested", file=sys.stderr)
        raise SystemExit(130)
    except (ImportError, RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
