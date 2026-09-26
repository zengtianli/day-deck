#!/usr/bin/env python3
"""重生图标：iOS 端与 Notihub Mac 共用同一张 Seedream 原图（2026-09-27 DayDeck 并入 Notihub）。
Resources/icon-src.png = ../../mac/icon/SeedreamSource.png 的副本；裁切参数与
../../mac/icon/provenance.json 的 crop_xy_side 一致（取铃铛瓷砖内侧、满幅方形、无透明），
圆角由 iOS 自己加。改图标 = 换 Mac 端原图后同步 icon-src.png 再跑本脚本。"""
import hashlib, json, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).parent
SRC = HERE / "Resources/icon-src.png"
MAC = HERE / "../../mac/icon"
if not SRC.exists():
    sys.exit("icon-src.png 不存在，拒绝生成（fail-closed）")
prov = json.loads((MAC / "provenance.json").read_text())
if hashlib.sha256(SRC.read_bytes()).hexdigest() != prov["source_sha256"]:
    sys.exit("icon-src.png 与 Mac 端原图不一致，先同步再生成（fail-closed）")
x, y, side = prov["packaging"]["crop_xy_side"]
out = HERE / "Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
subprocess.check_call(["magick", str(SRC), "-crop", f"{side}x{side}+{x}+{y}", "+repage",
                       "-resize", "1024x1024", "-alpha", "off", "-strip", f"PNG24:{out}"])
info = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "hasAlpha", str(out)], text=True)
assert "pixelWidth: 1024" in info and "hasAlpha: no" in info, info
print("icon-1024.png 已从 Notihub 原图派生")
