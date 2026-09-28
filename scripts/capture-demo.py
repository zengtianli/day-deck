#!/usr/bin/env python3
"""Record four real, read-only simulator clips; no desktop UI or synthetic input.

Run with the shared Python environment. A failed idle gate exits 75 before build,
installation, simulator creation or changes to existing footage. --check only
checks prerequisites and the gate. Chapter writes playback evidence separately.
"""
import argparse
import importlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check prerequisites and idle gate only")
    args = parser.parse_args()
    sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
    sop = importlib.import_module("app_sop")
    okay, reason = sop.steady()
    if not okay:
        print(f"BLOCKED: {reason}; no build, installation or recording performed", flush=True)
        return 75
    for executable in ("xcrun", "ffmpeg", "ffprobe"):
        if not shutil.which(executable):
            raise RuntimeError(f"Missing prerequisite: {executable}")
    if args.check:
        print(f"READY: {reason}; no simulator started")
        return 0

    # Sanitize build environment; never copy credentials into Xcode artifacts.
    environment = {k: v for k, v in os.environ.items()
                   if k in ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "SHELL", "LANG", "DEVELOPER_DIR")}
    device = None
    recorder = None
    staging = None
    (ROOT / "build").mkdir(exist_ok=True)
    try:
        staging = Path(tempfile.mkdtemp(prefix="notihub-demo-", dir=ROOT / "build"))
        name = "Notihub-public-" + uuid.uuid4().hex[:12]
        device = run("xcrun", "simctl", "create", name,
                     "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", env=environment).stdout.strip()
        if not device:
            raise RuntimeError("simctl did not return a device UUID")
        print("Building and installing Debug demo in a new private simulator", flush=True)
        with (staging / "build.log").open("w") as log:
            subprocess.run(["bash", "sim-run.sh", "--shutdown"], cwd=ROOT,
                           env={**environment, "SIM_NAME": name, "SIM_LAUNCH_ARGS": "-demo 1 -tab 0"},
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
        # Do not expose arbitrary build logs or copy the fresh simulator's data.
        print("Dedicated simulator prepared", flush=True)
        run("xcrun", "simctl", "boot", device)
        run("xcrun", "simctl", "bootstatus", device, "-b", timeout=60)
        installed_app = Path(run("xcrun", "simctl", "get_app_container", device, BUNDLE, "app").stdout.strip())
        info = plistlib.loads((installed_app / "Info.plist").read_bytes())
        clips = []
        for index, (title, tab, search) in enumerate(SECTIONS, 1):
            print(f"Recording {index}/4: {title}", flush=True)
            run("xcrun", "simctl", "launch", "--terminate-running-process", device, BUNDLE,
                "-demo", "1", "-tab", tab, "-search", search)
            time.sleep(2)  # Separate setup from the recorded, fully visible page.
            clip = staging / f"{index:02d}.mp4"
            with (staging / f"{index:02d}-capture.log").open("w") as log:
                recorder = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(clip)],
                                            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                time.sleep(6)
                if recorder.poll() is not None:
                    raise RuntimeError(f"Recorder exited before clip {index} finished; inspect {log.name}")
                recorder.send_signal(signal.SIGINT)
                recorder.wait(timeout=20)
                recorder = None
            duration = float(run("ffprobe", "-v", "error", "-show_entries", "format=duration",
                                 "-of", "default=nw=1:nk=1", str(clip)).stdout)
            if duration < 2:
                raise RuntimeError(f"Clip {index} too short ({duration}s)")
            run("ffmpeg", "-v", "error", "-i", str(clip), "-f", "null", "-", timeout=90)
            clips.append((clip, title, duration))

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
                    "environment": "iOS Simulator", "configuration": "Debug", "synthetic_data": True,
                    "coverage": "Four real read-only views, separately launched; no save/login/gesture demonstration",
                    "clips": [{"file": c.name, "title": t, "duration": d} for c, t, d in clips],
                    "visual_review": "pending", "playback_acceptance": "Run Chapter media_playback separately"}
        (staging / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
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
    finally:
        if recorder and recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
            try:
                recorder.wait(timeout=20)
            except subprocess.TimeoutExpired:
                recorder.kill()
                recorder.wait()
        if device:
            subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True, timeout=30)
            # Only the fresh, UUID-scoped device created in this invocation is deleted.
            subprocess.run(["xcrun", "simctl", "delete", device], capture_output=True, timeout=30)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ImportError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
