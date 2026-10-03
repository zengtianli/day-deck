#!/usr/bin/env python3
"""合成商店截图：--platform iphone|ipad|watch|vision；共用 sim_lane 的构建、隔离和旋转。"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import sys
import tempfile
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


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=DEVICES)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--reuse-build", type=Path, help="复用 sim_lane 的构建 JSON；源码副本必须逐文件匹配，iPad 可用 iPhone 包")
    args = parser.parse_args(argv)
    okay, reason = app_sop.steady(True, allow_owner_now=False)
    if not okay:
        print(f"推迟：{reason}；未构建、启动或截图", file=sys.stderr)
        return 75
    app = app_sop.load_apps("day-deck-ios")[0]
    inputs = app_sop.lane_inputs(app, args.platform)
    out = (args.out or REPO / "shots/appstore" / args.platform).resolve()
    work = Path(tempfile.mkdtemp(prefix="notihub-store-shots."))
    udid = None
    try:
        scheme = "DayDeckWatch" if args.platform == "watch" else "DayDeck"
        if args.reuse_build:
            built = sim_lane.reuse_build(args.reuse_build, app["id"], REPO, args.platform, scheme)
        else:
            built = sim_lane.build(REPO, scheme, args.platform, "Debug", work / "build")
        rows = []
        screens = WATCH if args.platform == "watch" else SCREENS
        for index, (name, extra) in enumerate(screens):
            okay, reason = app_sop.steady(True, allow_owner_now=False)
            if not okay:
                print(f"推迟：{reason}；候选截图未写回", file=sys.stderr)
                return 75
            png = work / f"{index + 1:02d}-{name}.png"
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
        print(f"推迟：{exc}", file=sys.stderr)
        return 75
    except sim_lane.LaneError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        if udid and args.platform != "mac":
            sim_lane.shutdown(udid)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
