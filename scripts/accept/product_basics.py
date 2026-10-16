#!/usr/bin/env python3
"""Current SDK candidate -> dedicated hidden simulator -> real in-process settings actions.

--prepare only builds; --app/--receipt verify a specified candidate, never claim device installation.
Default reuses the current-source build receipt and verifies the installed simulator copy before testing.
"""
import argparse
import hashlib
import json
import os
import plistlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane

PHASES = ("seed", "readback", "remote", "receive", "fallback", "corrupt", "recover", "disable", "updates")
RECEIPT = ROOT / "perf/product-basics/build-receipt.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(body, ensure_ascii=False, indent=2) + "\n")


def candidate(args):
    receipt = args.receipt or RECEIPT
    if receipt.exists() and not args.rebuild:
        built = sim_lane.reuse_build(receipt, "day-deck-ios", ROOT, "iphone", "DayDeck", "Debug")
    else:
        if args.app or args.receipt:
            raise ValueError("指定候选必须提供存在的原始 build receipt")
        built = sim_lane.build(ROOT, "DayDeck", "iphone", "Debug")
        write(receipt, built)
    app = Path(built["app_path"])
    if args.app and args.app.resolve() != app.resolve():
        raise ValueError("--app 与原始 receipt 的包路径不符")
    return app, receipt, built


def run(args):
    app, receipt, built = candidate(args)
    if args.prepare:
        print(json.dumps({"candidate": str(app), "receipt": str(receipt), "installed_on_phone": False}, ensure_ascii=False))
        return 0
    spec = json.loads(os.environ["SOP_PRODUCT_BASICS_SPEC"])
    out = Path(os.environ["SOP_OUT_DIR"]).resolve()
    run_dir = out / ("product-basics-" + uuid.uuid4().hex)
    run_dir.mkdir(parents=True)
    dev = sim_lane.ensure_device("iphone", name="Notihub-product-basics-" + uuid.uuid4().hex[:10])
    if not dev.get("created"):
        raise ValueError("隔离基础验收拒绝使用既有模拟器，未安装或修改数据")
    records, checks = {}, {}
    phase = "install"
    data = None
    try:
        with sim_lane.Session("iphone", dev["udid"], label="day-deck-ios:product-basics", lock_wait=0, load_wait=0) as session:
            session.install(app)
            bundle = built["bundle_id"]
            installed = Path(sim_lane.simctl("get_app_container", dev["udid"], bundle, "app").stdout.strip())
            data = Path(sim_lane.simctl("get_app_container", dev["udid"], bundle, "data").stdout.strip())
            # Both Debug loader and actual code are bound; loader SHA alone cannot prove current implementation.
            executable = sim_lane.bundle_info(app)["executable"]
            names = [Path(executable).name, Path(executable).name + ".debug.dylib", "Info.plist"]
            checks["settings.installed_simulator_candidate_identity"] = all(sha(app / name) == sha(installed / name) for name in names)
            code_hashes = {name: sha(installed / name) for name in names}
            status = subprocess.run([sys.executable, str(Path(__file__).resolve()), "--status", "--udid", dev["udid"]],
                                    cwd=ROOT, capture_output=True, text=True, timeout=30)
            (run_dir / "installed-status.json").write_text(status.stdout)
            readback = json.loads(status.stdout)
            checks["settings.cli_status_readback"] = status.returncode == 0 and readback["bundle_id"] == bundle and str(readback["build"]) == str(built["build"])
            for phase in PHASES:
                print(f"product_basics phase={phase}", flush=True)
                result = data / "Documents/product-basics" / (phase + ".json")
                # Every phase writes its atomic record and exits itself. Asking SpringBoard to
                # terminate that already-exiting process races with the next launch. A fresh
                # device and the PID/phase checks below still reject a reused running process.
                proc = sim_lane.simctl("launch", dev["udid"], bundle,
                                      "--ui-self-test", phase, timeout=60)
                (run_dir / (phase + ".launch.log")).write_text(proc.stdout + proc.stderr)
                launched = re.search(r":\s*(\d+)\s*$", proc.stdout.strip())
                if not launched:
                    raise RuntimeError(f"{phase} 启动没有实际进程 PID")
                deadline = time.monotonic() + 70
                while not result.exists() and time.monotonic() < deadline:
                    time.sleep(.25)
                if not result.exists():
                    raise RuntimeError(f"真实 App 未生成 {phase} 原件")
                records[phase] = json.loads(result.read_text())
                shutil.copyfile(result, run_dir / (phase + ".json"))
                if records[phase].get("phase") != phase or records[phase].get("process_id") != int(launched[1]):
                    raise RuntimeError(f"{phase} 原件与实际启动进程不符")
                row = records[phase]["checks"]
                if not row or any(type(v) is not bool for v in row.values()):
                    raise RuntimeError(f"{phase} checks 无效")
                checks.update(row)
                if not all(row.values()):
                    raise RuntimeError(f"{phase} 失败: {[k for k,v in row.items() if not v]}; {records[phase]['observations']}")
            for name in ("settings.png", "updates.png", "export.json", "store-fixture.json"):
                shutil.copyfile(data / "Documents/product-basics" / name, run_dir / name)
            for name in ("settings.png", "updates.png"):
                with Image.open(run_dir / name) as image:
                    colors = image.convert("RGB").resize((215, 550)).getcolors(215 * 550) or []
                    total = 215 * 550
                    checks["settings." + name.split(".")[0] + "_nonblank"] = len(colors) > 100 and max(n for n, _ in colors) / total < .97
            checks["settings.separate_processes"] = len({r["process_id"] for r in records.values()}) == len(PHASES)
    except sim_lane.Busy:
        raise
    except Exception as exc:
        # Preserve synthetic self-test output before deleting the owned device. A launch
        # timeout must not discard a result produced by the App, or hide the failing phase.
        if data is not None:
            source = data / "Documents/product-basics"
            for name in [p + ".json" for p in PHASES] + ["settings.png", "updates.png", "export.json", "store-fixture.json"]:
                file = source / name
                if file.is_file():
                    shutil.copyfile(file, run_dir / name)
        write(run_dir / "failure.json", {
            "schema_version": 1, "environment": "simulator", "phase": phase,
            "error": str(exc), "device": dev, "candidate_receipt_sha256": sha(receipt),
            "completed_phases": list(records),
            "artifacts": {p.name: sha(p) for p in run_dir.iterdir() if p.is_file()},
        })
        print(f"product_basics failure evidence: {run_dir / 'failure.json'}", file=sys.stderr)
        raise
    finally:
        if dev["created"]:
            sim_lane.simctl("delete", dev["udid"], check=False)
    def all_of(*keys):
        return all(checks.get(k) is True for k in keys)
    checks.update({
        "settings.interaction": all_of("settings.control_saved", "settings.export_import", "settings.close_action", "settings.offscreen_view_rendered"),
        "settings.persisted_readback": all_of("settings.fresh_process_readback", "settings.separate_processes"),
        "settings.error_preserves_data": all_of("settings.invalid_selection_preserved", "settings.malformed_preserved", "settings.invalid_import_preserved"),
        "icloud.push_pull": all_of("icloud.push", "icloud.cloud_file_written", "icloud.fresh_device_pull", "icloud.empty_device_does_not_overwrite", "icloud.second_device_push", "icloud.remote_change_applied"),
        "icloud.unavailable_local_fallback": all_of("icloud.unavailable_reports_error", "icloud.unavailable_preserves_file", "icloud.offline_local_write"),
        "icloud.conflict_or_corrupt_recovery": all_of("icloud.corrupt_reports_error", "icloud.corrupt_preserves_local", "icloud.recovery_reconcile", "icloud.offline_edit_wins_conflict", "icloud.merged_cloud_readback"),
        "icloud.disable_preserves_data": all_of("icloud.disable_keeps_existing_local", "icloud.disable_keeps_cloud", "icloud.disabled_local_usable"),
        "updates.check_result": all_of("updates.fixture_version_read", "updates.actual_apple_request_completed"),
        "updates.failure_recovery": all_of("updates.bad_source_reported", "updates.fixture_version_read", "updates.open_failure_reported"),
        "updates.options_or_store_entry": all_of("updates.store_and_beta_entry_actions"),
        "updates.data_preservation": all_of("updates.checks_preserve_configuration", "updates.checks_preserve_private_draft", "updates.synchronization_stays_disabled"),
    })
    raw = {"schema_version": 1, "app_id": os.environ["SOP_APP_ID"], "spec_digest": spec["digest"],
           "checks": checks, "environment": "simulator", "device": dev,
           "candidate": {"app": str(app), "receipt": str(receipt), "receipt_sha256": sha(receipt),
                         "source_verification": built.get("reuse"),
                         "installed_simulator_code": code_hashes, "installed_on_phone": False},
           "scope": "Real Debug App, hidden simulator, detached native settings hierarchy; isolated two-client configuration transport, not Apple cross-device transfer; real Apple lookup plus version-source fixtures; store opens captured without changing focus.",
           "records": records, "artifacts": {p.name: sha(p) for p in run_dir.iterdir() if p.is_file()}}
    raw_path = run_dir / "raw.json"
    write(raw_path, raw)
    features = {}
    for key, declared in spec["features"].items():
        if declared["state"] == "not_applicable":
            features[key] = {"result": "not_applicable", "reason": declared["reason"]}
        else:
            keys = [k for k in checks if k.startswith(key + ".")]
            features[key] = {"result": "passed" if all(checks[k] for k in keys) else "failed",
                             "method": "ui_automation" if key == "settings" else "real_product",
                             "evidence": str(raw_path.relative_to(ROOT)), "evidence_sha256": sha(raw_path), "checks": keys}
    passed = all(checks.values())
    detail = {"schema_version": 1, "app_id": raw["app_id"], "spec_digest": raw["spec_digest"], "features": features,
              "summary": f"模拟器真实产品基础验收：{len(checks)} 项检查；快捷键按触屏边界不适用；iCloud 为隔离链路", "scope": raw["scope"]}
    write(out / "product_basics.detail.json", detail)
    print(detail["summary"])
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--status", action="store_true", help="只读指定模拟器中已装 App 的版本与配置，不启动 App")
    parser.add_argument("--udid", help="--status 的明确模拟器 UUID")
    args = parser.parse_args()
    if bool(args.app) != bool(args.receipt):
        parser.error("--app 与 --receipt 必须一起提供")
    try:
        if args.status:
            if not args.udid:
                parser.error("--status 必须提供 --udid")
            bundle = "cyou.tianli.daydeck"
            app = Path(sim_lane.simctl("get_app_container", args.udid, bundle, "app").stdout.strip())
            data = Path(sim_lane.simctl("get_app_container", args.udid, bundle, "data").stdout.strip())
            info = plistlib.loads((app / "Info.plist").read_bytes())
            file = data / "Library/Application Support/Notihub/preferences.json"
            prefs = data / "Library/Preferences" / (bundle + ".plist")
            defaults = plistlib.loads(prefs.read_bytes()) if prefs.exists() else {}
            configuration = json.loads(file.read_text()) if file.exists() else {}
            print(json.dumps({"environment": "simulator", "bundle_id": info["CFBundleIdentifier"],
                              "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                              "startup_page": configuration.get("startupTab", 0),
                              "icloud_enabled": defaults.get("appLifecycle.configuration.enabled", False),
                              "update_store_id": "6807048407", "distribution": "TestFlight 内测；商店未发行时检查会报未找到"}, ensure_ascii=False))
            return 0
        return run(args)
    except sim_lane.Busy as exc:
        print(f"等待原模拟器队列：{exc}", file=sys.stderr)
        return 75
    except Exception as exc:
        print(f"product_basics failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
