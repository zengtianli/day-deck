#!/usr/bin/env python3
"""Does the iPhone (compact) UI still render exactly as the recorded demo? Same data, two builds, pixel diff.

    ~/Dev/.venv/bin/python scripts/media/compact_unchanged.py [--base HEAD] [--out DIR]

The public demo video (shots/public-demo.mp4) and the iPhone screenshots show the compact layout: four tabs. Since
2026-10-02 the same target also draws the wide layout (iPad / Vision Pro) and embeds an Apple Watch app, so every UI
change has to show that the compact screens did not move. This builds the --base commit (default HEAD) and the current
working tree as Debug simulator builds (the synthetic `-demo 1` data is DEBUG-only) through the shared sim_lane (copies
outside the repo, unsigned), and on one iPhone 17 Pro simulator (shared lock, load gate, headless, status bar pinned to
9:41) renders each screen for base, current, and base again (control): today, notifications, notifications searching
"房东", diary, connection. A screen passes when current is identical to base, or no pixel differs by more than 2
levels in any channel (the iOS 26+ glass tab bar renders with ±1 noise; base shows the same against its own control
run), or every pixel that differs by more lies within the rows where base differs from its own control run, or (on
the connection screen only) within one trailing text row: "最近同步 2 min, 7 sec" is a live relative timestamp that ticks
every second, so base and its control may or may not catch the same second.

    --compare-only DIR   re-judge an earlier run's DIR/{base,current,control}/*.png without building or booting

Exit 0 unchanged, 1 changed or failed, 75 simulator lock held / machine loaded (run again later).
Copied from the PointsDeck pilot (edu/ios/points scripts/media/compact_unchanged.py) and cut to this app's screens.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BUNDLE = "cyou.tianli.daydeck"
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane  # noqa: E402

DEMO = ["-demo", "1"]
SCREENS = [("today", ["-tab", "0"]), ("recap", ["-tab", "1"]), ("search", ["-tab", "1", "-search", "房东"]),
           ("diary", ["-tab", "2"]), ("connection", ["-tab", "3"])]
NOISE = 2             # max channel difference treated as rendering noise (glass materials), not a layout change
# Screens with a ticking value the app draws itself: 连接 → 云端 → 最近同步 is Text(date, style: .relative) ("2 min, 7 sec").
# Differences there are accepted only when they fit one text row (<= 64 px tall) in the right half (the trailing value).
VOLATILE = {"connection": "最近同步 relative timestamp"}
VOLATILE_ROW_PX = 64
RULE = (f"identical; or no pixel differs by more than {NOISE} levels in any channel (rendering noise); or every pixel "
        f"differing by more lies within the rows where base differs from its own control run; connection: or within "
        f"one trailing text row (<= {VOLATILE_ROW_PX} px, the live 最近同步 timestamp)")


def sha(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def shots(udid: str, s, app: Path, out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    sim_lane.simctl("uninstall", udid, BUNDLE, check=False)
    s.install(app)
    hashes = {}
    for name, extra in SCREENS:
        sim_lane.simctl("launch", "--terminate-running-process", udid, BUNDLE, *DEMO, *extra, timeout=120)
        time.sleep(6)     # base builds predate the lane-ready log; the same fixed wait for both sides
        a, b = out / f".{name}.a.png", out / f"{name}.png"
        s.shot(a)
        for _ in range(8):
            time.sleep(1.2)
            s.shot(b)
            if sim_lane.Frame(b, "iphone").diff(sim_lane.Frame(a, "iphone")) <= 0.0005:
                break
            shutil.copyfile(b, a)
        a.unlink(missing_ok=True)
        hashes[name] = sha(b)
        s.terminate(BUNDLE)
    sim_lane.simctl("uninstall", udid, BUNDLE, check=False)
    return hashes


def diff(a: Path, b: Path) -> dict:
    from PIL import Image, ImageChops
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return {"identical": False, "size_mismatch": [ia.size, ib.size]}
    d = ImageChops.difference(ia, ib)
    bbox = d.getbbox()
    if bbox is None:
        return {"identical": True, "diff_pixels": 0, "significant_pixels": 0}
    # per pixel: the largest channel difference
    r, g, b = d.split()
    peak = ImageChops.lighter(ImageChops.lighter(r, g), b)
    hist = peak.histogram()
    significant = peak.point(lambda v: 255 if v > NOISE else 0)
    return {"identical": False, "diff_pixels": sum(hist[1:]), "diff_bbox": list(bbox),
            "max_channel_diff": max(i for i, n in enumerate(hist) if n),
            "significant_pixels": sum(hist[NOISE + 1:]),
            "significant_bbox": (lambda x: list(x) if x else None)(significant.getbbox())}


def same_rows(inner: list[int], outer: list[int] | None, pad: int = 4) -> bool:
    """inner lies within outer's rows (any x): a ticking timestamp changes width, so its x-extent moves between runs."""
    return bool(outer) and inner[1] >= outer[1] - pad and inner[3] <= outer[3] + pad


def judge(cur: dict, control: dict, name: str = "", width: int = 1206) -> tuple[bool, str]:
    if cur.get("identical"):
        return True, "identical"
    if "size_mismatch" in cur:
        return False, f"size {cur['size_mismatch']}"
    if not cur["significant_pixels"]:
        return True, (f"{cur['diff_pixels']} px differ by <= {NOISE} levels (rendering noise; base vs its own control: "
                      f"{control.get('diff_pixels', 0)} px, max {control.get('max_channel_diff', 0)})")
    if same_rows(cur["significant_bbox"], control.get("significant_bbox")):
        return True, (f"{cur['significant_pixels']} px > {NOISE} levels at {cur['significant_bbox']}, all within the rows "
                      f"base differs from itself (control {control['significant_bbox']}; live timestamp)")
    box = cur["significant_bbox"]
    if name in VOLATILE and box[3] - box[1] <= VOLATILE_ROW_PX and box[0] >= width // 2:
        return True, (f"{cur['significant_pixels']} px > {NOISE} levels at {box}: one trailing text row, "
                      f"the {VOLATILE[name]} (ticks every second)")
    return False, f"{cur['significant_pixels']} px differ by > {NOISE} levels at {box}"


def compare(out: Path) -> dict:
    screens = {}
    for name, _ in SCREENS:
        cur = diff(out / "base" / f"{name}.png", out / "current" / f"{name}.png")
        control = diff(out / "base" / f"{name}.png", out / "control" / f"{name}.png")
        from PIL import Image
        ok, why = judge(cur, control, name, Image.open(out / "base" / f"{name}.png").size[0])
        screens[name] = {"ok": ok, "verdict": why, "current_vs_base": cur, "control_vs_base": control,
                         **{f"{side}_sha256": sha(out / side / f"{name}.png") for side in ("base", "current", "control")}}
    return screens


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="HEAD", help="git revision the existing media were last reviewed against")
    ap.add_argument("--out", type=Path, help="keep screenshots and report here (outside the repo); default a temp dir")
    ap.add_argument("--compare-only", type=Path, help="re-judge an earlier run's screenshots; no build, no simulator")
    a = ap.parse_args(argv)
    if a.compare_only:
        screens = compare(a.compare_only)
        ok = all(v["ok"] for v in screens.values())
        summary = a.compare_only / "summary.json"
        if summary.is_file():   # keep the run's build/device facts, replace the verdicts with the current rule's
            report = json.loads(summary.read_text(encoding="utf-8"))
            report.update(screens=screens, unchanged=ok, rule=RULE,
                          rejudged_at=dt.datetime.now().astimezone().isoformat(timespec="seconds"))
            summary.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(json.dumps({"unchanged": ok, "screens": {k: v["verdict"] for k, v in screens.items()}}, ensure_ascii=False))
        return 0 if ok else 1
    base = subprocess.run(["git", "-C", str(REPO), "rev-parse", a.base], capture_output=True, text=True, check=True).stdout.strip()
    work = Path(tempfile.mkdtemp(prefix="daydeck-compact."))
    out = (a.out or work / "out").expanduser().resolve()
    if out == REPO or out.is_relative_to(REPO):
        print("--out 必须在仓外", file=sys.stderr)
        return 2
    started = dt.datetime.now().astimezone()
    try:
        src_base = work / "base-src"
        src_base.mkdir()
        tar = subprocess.run(["git", "-C", str(REPO), "archive", base], capture_output=True, check=True).stdout
        subprocess.run(["tar", "-x", "-C", str(src_base)], input=tar, check=True)
        built = {"base": sim_lane.build(src_base, "DayDeck", "iphone", "Debug", work / "base"),
                 "current": sim_lane.build(REPO, "DayDeck", "iphone", "Debug", work / "current")}
        dev = sim_lane.ensure_device("iphone", "iPhone-17-Pro")
        with sim_lane.Session("iphone", dev["udid"], label="day-deck compact_unchanged") as s:
            sim_lane.simctl("status_bar", dev["udid"], "override", "--time", "9:41", "--dataNetwork", "wifi",
                            "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
                            "--batteryState", "charged", "--batteryLevel", "100", check=False)
            for side, key in (("base", "base"), ("current", "current"), ("control", "base")):
                shots(dev["udid"], s, Path(built[key]["app_path"]), out / side)
    except sim_lane.Busy as exc:
        print(f"推迟：{exc}", file=sys.stderr)
        return 75
    screens = compare(out)
    unchanged = all(v["ok"] for v in screens.values())
    report = {"schema_version": 1, "app": "day-deck-ios", "checked_at": started.isoformat(timespec="seconds"),
              "base_commit": base, "device": f"{dev['name']} ({dev['device_type']}) / {dev['runtime'].rsplit('.', 1)[-1]} simulator",
              "builds": {k: {x: v.get(x) for x in ("version", "build", "executable_sha256", "sdk", "configuration")}
                         for k, v in built.items()},
              "data": "synthetic -demo 1 (Sources/DemoFeed.swift), same for every build, status bar 9:41",
              "rule": RULE,
              "screens": screens, "unchanged": unchanged}
    (out / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    shutil.rmtree(work / "base", ignore_errors=True)
    shutil.rmtree(work / "current", ignore_errors=True)
    print(json.dumps({"unchanged": unchanged, "out": str(out),
                      "screens": {k: v["verdict"] for k, v in screens.items()}}, ensure_ascii=False))
    return 0 if unchanged else 1


if __name__ == "__main__":
    sys.exit(main())
