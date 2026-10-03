#!/usr/bin/env python3
"""合成商店截图：--platform iphone|ipad|watch|vision；共用 sim_lane 的构建、隔离和旋转。"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import json
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import app_sop
import sim_lane
import store_shots as spec

DEVICES = {"iphone": "iPhone-17-Pro-Max", "ipad": "iPad-Pro-13-inch-M5-12GB",
           "watch": "Apple-Watch-Series-12-46mm", "vision": "Apple-Vision-Pro-4K"}
SCREENS = [("today", ["-tab", "0"]), ("notifications", ["-tab", "1"]),
           ("diary", ["-tab", "2"]), ("connection", ["-tab", "3"])]
WATCH = [("glance", []), ("sources", ["-tab", "1"]), ("highlights", ["-tab", "2"]),
         ("complications", ["-complications", "1"])]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def capture_gate(in_use, phase):
    okay, reason = app_sop.steady(not in_use, allow_owner_now=False)
    on_ac = "AC Power" in app_sop.sh(["pmset", "-g", "batt"]).stdout
    power = app_sop.sh(["pmset", "-g"]).stdout
    setting = re.search(r"^\s*lowpowermode\s+(\d+)\s*$", power, re.M)
    low_power = int(setting.group(1)) if setting else None
    reasons = [] if okay else [reason]
    if not on_ac:
        reasons.append("没接电源")
    if low_power == 1:
        reasons.append("低电量模式会压低性能")
    observation = {"phase": phase, "observed_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
                   "steady": {"user_away": not in_use, "allow_owner_now": False,
                              "okay": okay, "reason": reason},
                   "ac_power": on_ac, "low_power_mode": low_power,
                   "allowed": not reasons, "reason": "；".join(dict.fromkeys(reasons)) or reason}
    return observation


def capture_budget(deadline, needed=0):
    if time.monotonic() + needed > deadline - 180:
        raise sim_lane.Busy("同次截图 2400 秒预算不足，保留 180 秒原 Session 清理")


def wait_capture_gate(in_use, phase, execution, deadline):
    budget = execution["stabilization"]
    while True:
        capture_budget(deadline)
        if budget["wait_seconds"] >= 180:
            raise sim_lane.Busy("同次稳定等待已达 180 秒，候选截图未写回")
        gate = capture_gate(in_use, phase)
        execution["gate_observations"].append(gate)
        if gate["allowed"]:
            return
        # Only post-boot load can settle here; owner activity, power and other builds still defer immediately.
        if (not gate["ac_power"] or gate["low_power_mode"] == 1
                or "构建" in gate["steady"]["reason"] or "用户" in gate["steady"]["reason"]):
            raise sim_lane.Busy(gate["reason"])
        delay = min(10, 180 - budget["wait_seconds"], deadline - 180 - time.monotonic())
        if delay <= 0:
            raise sim_lane.Busy(gate["reason"] + "；同次稳定等待预算用完")
        started = time.monotonic()
        time.sleep(delay)
        budget["wait_seconds"] += time.monotonic() - started


def session_result(session, info, dev, launch, png, install_seconds, deadline):
    capture_budget(deadline, 500)  # original baseline/launch/shot limits, plus the reserved cleanup
    baseline, stable = session.baseline()
    actual = session.launch(info["bundle_id"], launch, "auto", 90, baseline, info["executable"])
    frame = actual.get("frame")
    if frame:
        shutil.copyfile(frame.path, png)
    session.terminate(info["bundle_id"])
    verdict = actual.get("verdict") or {}
    result = {"ok": bool(actual.get("ready_signal") and verdict.get("non_blank")
                         and verdict.get("changed_from_baseline") and not actual["errors"]),
              "platform": session.platform, "udid": session.udid, "device": dev["name"],
              "device_type": dev["device_type"], "runtime": dev["runtime"].rsplit(".", 1)[-1],
              "bundle_id": info["bundle_id"], "version": info["version"], "build": info["build"],
              "launch_args": sim_lane.redact_args(launch), "environment": "simulator",
              "boot_seconds": session.boot_seconds, "install_seconds": install_seconds,
              "baseline_stable": stable, "screenshot": str(png),
              "frame_source": str(frame.path) if frame else None,
              **{key: actual[key] for key in ("pid", "ready_seconds", "ready_signal", "verdict", "errors", "notes")},
              "shutdown": False, "capture_method": "single original sim_lane.Session"}
    if frame:
        result["size"] = list(spec.png_size(png))
    return result


def deferred(reason, execution):
    print(f"推迟：{reason}；候选截图未写回", file=sys.stderr)
    print(json.dumps({"ok": False, "deferred": True, "reason": reason,
                      "capture_execution": execution}, ensure_ascii=False))
    return 75


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=DEVICES)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--reuse-build", type=Path, help="复用 sim_lane 的构建 JSON；源码副本必须逐文件匹配，iPad 可用 iPhone 包")
    parser.add_argument("--in-use", action="store_true", help="本人明确授权使用中无界面截图；仅 iPhone/Vision/Watch 且须 --reuse-build，保留接电/低负载/无构建/非低电量门")
    args = parser.parse_args(argv)
    deadline = time.monotonic() + 2400
    execution = {"in_use": args.in_use, "user_authorization": "explicit --in-use" if args.in_use else None,
                 "command_args": list(sys.argv[1:] if argv is None else argv),
                 "gate_policy": {"idle_seconds_minimum": 0 if args.in_use else 600,
                                 "require_ac": True, "allow_owner_now": False,
                                 "low_power_mode_allowed": False, "sdk_build_allowed": not args.in_use},
                 "gate_observations": [],
                 "stabilization": {"wait_seconds_limit": 180, "wait_seconds": 0}}
    if args.in_use and (args.platform == "ipad" or args.reuse_build is None):
        return deferred("使用中只接受无需旋转的 iPhone/Vision/Watch 和显式 --reuse-build；iPad 保留原闲置路线", execution)
    gate = capture_gate(args.in_use, "initial")
    execution["gate_observations"].append(gate)
    if not gate["allowed"]:
        return deferred(gate["reason"], execution)
    app = app_sop.load_apps("day-deck-ios")[0]
    inputs = app_sop.lane_inputs(app, args.platform)
    out = (args.out or REPO / "shots/appstore" / args.platform).resolve()
    work = Path(tempfile.mkdtemp(prefix="notihub-store-shots."))
    udid = None
    single_session = args.platform == "iphone" or args.in_use
    native = contextlib.ExitStack()
    try:
        scheme = "DayDeckWatch" if args.platform == "watch" else "DayDeck"
        if args.reuse_build:
            built = sim_lane.reuse_build(args.reuse_build, app["id"], REPO, args.platform, scheme)
        else:
            built = sim_lane.build(REPO, scheme, args.platform, "Debug", work / "build")
        if single_session:
            app_path = Path(built["app_path"])
            info = sim_lane.bundle_info(app_path)
            sim_lane.mark_used(app_path)
            dev = sim_lane.ensure_device(args.platform, DEVICES[args.platform], None)
            capture_budget(deadline, 420)
            session = native.enter_context(sim_lane.Session(args.platform, dev["udid"], keep_booted=False,
                                                            lock_wait=0, load_wait=0))
            udid = session.udid
            execution["native_session"] = {"platform": session.platform, "udid": session.udid,
                                           "label": session.label, "keep_booted": False,
                                           "cleanup_completed": False}
            wait_capture_gate(args.in_use, "postboot", execution, deadline)
            capture_budget(deadline, 600)
            install_seconds = session.install(app_path)
        rows = []
        screens = WATCH if args.platform == "watch" else SCREENS
        for index, (name, extra) in enumerate(screens):
            png = work / f"{index + 1:02d}-{name}.png"
            if single_session:
                wait_capture_gate(args.in_use, "screen:" + name, execution, deadline)
                result = session_result(session, info, dev, ["-demo", "1", *extra], png, install_seconds, deadline)
            else:
                gate = capture_gate(args.in_use, "screen:" + name)
                execution["gate_observations"].append(gate)
                if not gate["allowed"]:
                    return deferred(gate["reason"], execution)
                result = sim_lane.run_sim(args.platform, Path(built["app_path"]), udid, None,
                                          DEVICES[args.platform], ["-demo", "1", *extra], png, 90,
                                          index < len(screens) - 1, "auto", 0, 0, None,
                                          orientation="landscape" if args.platform == "ipad" else None)
            udid = result["udid"]
            if not result["ok"]:
                raise sim_lane.LaneError(json.dumps(result["errors"], ensure_ascii=False))
            rows.append({"file": png.name, "sha256": sha(png), "size": list(spec.png_size(png)),
                         "launch_args": result["launch_args"], "ready_seconds": result["ready_seconds"],
                         "lane_result": result,
                         "device": result["device"], "runtime": result["runtime"], "environment": "simulator"})
        native.close()
        if single_session:
            execution["native_session"]["cleanup_completed"] = True
        problems = spec.validate(args.platform, [work / row["file"] for row in rows])
        if problems:
            raise sim_lane.LaneError("；".join(problems))
        if app_sop.lane_inputs(app, args.platform)["input_sha256"] != inputs["input_sha256"]:
            raise sim_lane.LaneError("截图期间源码改变，候选不写回")
        out.mkdir(parents=True, exist_ok=True)
        for row in rows:
            shutil.copyfile(work / row["file"], out / row["file"])
        report = {"schema_version": 1, "app": app["id"], "platform": args.platform,
                  "captured_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
                  "input_sha256": inputs["input_sha256"], "files": rows, "store_spec_issues": [],
                  "source_snapshot": inputs,
                  "capture_execution": execution,
                  "reused_build": bool(args.reuse_build),
                  "build_reuse": built.get("reuse"),
                  "build": {k: built[k] for k in ("configuration", "version", "build", "executable_sha256", "sdk")},
                  "scope": "DEBUG 合成数据；不是实际业务读写、性能实测或上架回执"}
        exe = Path(sim_lane.bundle_info(Path(built["app_path"]))["executable"])
        dylib = exe.with_name(exe.name + ".debug.dylib")
        if dylib.is_file():
            report["build"]["debug_code_sha256"] = sha(dylib)
        (out / "capture.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"ok": True, "platform": args.platform, "files": len(rows), "out": str(out)}, ensure_ascii=False))
        return 0
    except sim_lane.Busy as exc:
        native.close()
        if execution.get("native_session"):
            execution["native_session"]["cleanup_completed"] = True
        return deferred(str(exc), execution)
    except sim_lane.LaneError as exc:
        native.close()
        if execution.get("native_session"):
            execution["native_session"]["cleanup_completed"] = True
        print(str(exc), file=sys.stderr)
        print(json.dumps({"ok": False, "error": str(exc), "capture_execution": execution}, ensure_ascii=False))
        return 1
    finally:
        native.close()
        if udid and not single_session:
            sim_lane.shutdown(udid)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
