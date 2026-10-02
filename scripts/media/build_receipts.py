#!/usr/bin/env python3
"""Notihub 的持久构建回执入口；只调用共享 sim_lane，不启动模拟器。"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=("iphone", "vision", "watch"))
    parser.add_argument("--out", required=True, type=Path, help="仓外目录；保留包供测量和截图复用")
    parser.add_argument("--fixture-debug", action="store_true", help="Release -O，打开现有 DEBUG 合成数据入口")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--reuse-build", type=Path, help="严格复用已有原样回执；核验失败直接停止")
    group.add_argument("--from-iphone", type=Path, help="Watch 从同配置 iPhone 包中读取实际嵌入的 Watch App")
    args = parser.parse_args(argv)
    out = args.out.expanduser().resolve()
    if out == REPO or out.is_relative_to(REPO) or REPO.is_relative_to(out):
        parser.error("--out 必须在源码仓外")
    if args.from_iphone and args.platform != "watch":
        parser.error("--from-iphone 只适用于 Watch")
    suffix = "fixture" if args.fixture_debug else "release"
    receipt = out / f"{args.platform}-{suffix}.json"
    scheme = "DayDeckWatch" if args.platform == "watch" else "DayDeck"
    try:
        if args.reuse_build or receipt.is_file():
            built = sim_lane.reuse_build(args.reuse_build or receipt, "day-deck-ios", REPO,
                                         args.platform, scheme, "Release", args.fixture_debug)
        elif args.from_iphone:
            parent = sim_lane.reuse_build(args.from_iphone, "day-deck-ios", REPO,
                                          "iphone", "DayDeck", "Release", args.fixture_debug)
            watch_app = Path(parent["app_path"]) / "Watch/DayDeckWatch.app"
            if not watch_app.is_dir():
                raise sim_lane.LaneError("iPhone 包没有嵌入 Watch App；需单独构建 Watch，不派生虚假回执")
            info = sim_lane.bundle_info(watch_app)
            built = {**parent, "platform": "watch", "scheme": "DayDeckWatch",
                     "app_path": str(watch_app), "destination": "generic/platform=watchOS Simulator",
                     **{key: info[key] for key in ("bundle_id", "version", "build", "sdk")},
                     "executable_sha256": sim_lane.sha256(Path(info["executable"])),
                     "embedded_watch_origin": {"receipt": str(args.from_iphone.resolve()),
                                               "receipt_sha256": sim_lane.sha256(args.from_iphone),
                                               "iphone_app": parent["app_path"]}}
            built.pop("reuse", None)
        else:
            built = sim_lane.build(REPO, scheme, args.platform, "Release",
                                    out / f"{args.platform}-{suffix}", fixture_debug=args.fixture_debug)
        out.mkdir(parents=True, exist_ok=True)
        receipt.write_text(json.dumps(built, ensure_ascii=False, indent=2) + "\n")
        # 对派生 Watch 回执也执行相同共享校验；不把父包字段当成 Watch 身份。
        if args.from_iphone:
            sim_lane.reuse_build(receipt, "day-deck-ios", REPO, "watch", scheme,
                                 "Release", args.fixture_debug)
        print(json.dumps({"ok": True, "receipt": str(receipt), "app_path": built["app_path"]},
                         ensure_ascii=False))
        return 0
    except sim_lane.Busy as exc:
        print(f"推迟：{exc}", file=sys.stderr)
        return 75
    except sim_lane.LaneError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
