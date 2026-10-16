#!/usr/bin/env python3
"""Real App login actions, HTTPS read/write/readback and detached UIKit rendering.

Credentials enter only a fresh simulator's private data container after building.
No credential enters a build, environment, launch argument, log, or public evidence.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import time
import uuid
from PIL import Image
from product_basics import candidate, sim_lane, ROOT

REQUIRED = {
    "native.login_action", "native.active_review_api", "native.keychain_roundtrip",
    "privacy.separate_cache", "privacy.personal_cache_preserved", "privacy.personal_draft_preserved",
    "privacy.review_draft_separate", "privacy.owner_api_rejected", "cloud.index_and_open",
    "cloud.summary_and_timeline", "cloud.note_receipt", "cloud.note_retry_receipt",
    "cloud.fresh_store_note_once", "cloud.agenda_done_receipt", "cloud.agenda_done_readback",
    "cloud.agenda_restored", "native.offscreen_form", "native.return_action",
}


class AcceptanceError(RuntimeError):
    """Only fixed, credential-free diagnostics may be printed."""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--credentials", type=Path, default=Path.home() / "Library/Application Support/Notihub/app-review/credentials.json")
    args = parser.parse_args()
    if not args.prepare:
        path = args.credentials
        if (path.is_symlink() or not path.is_file() or path.stat().st_uid != os.getuid()
                or stat.S_IMODE(path.stat().st_mode) != 0o600 or path.parent.is_symlink()
                or stat.S_IMODE(path.parent.stat().st_mode) != 0o700):
            raise AcceptanceError("专用审核凭据尚未就绪或保护权限不正确")
    app, receipt, built = candidate(args)
    if args.prepare:
        print(json.dumps({"candidate": str(app), "receipt": str(receipt), "installed_on_phone": False}))
        return 0
    value = json.loads(args.credentials.read_text())
    if value.get("bundle_id") != "cyou.tianli.daydeck" or value.get("base_url") != "https://day.tianli.cyou/review":
        raise AcceptanceError("审核凭据所属产品或服务不匹配")
    # Do not copy the service's sync token, proxy secret, salt or password hash to the App.
    credential = {key: value[key] for key in ("username", "password")}
    out = Path(os.environ["SOP_OUT_DIR"]).resolve()
    run = out / ("review-native-" + uuid.uuid4().hex)
    run.mkdir(parents=True)
    dev = sim_lane.ensure_device("iphone", name="Notihub-review-" + uuid.uuid4().hex[:12])
    if not dev["created"]:
        raise AcceptanceError("原生审核验收拒绝使用既有模拟器，未安装或修改数据")
    input_path = None
    try:
        with sim_lane.Session("iphone", dev["udid"], label="day-deck-ios:review-native", lock_wait=0, load_wait=0) as session:
            session.install(app)
            bundle = built["bundle_id"]
            installed = Path(sim_lane.simctl("get_app_container", dev["udid"], bundle, "app").stdout.strip())
            data = Path(sim_lane.simctl("get_app_container", dev["udid"], bundle, "data").stdout.strip())
            executable = Path(sim_lane.bundle_info(app)["executable"]).name
            names = [executable, executable + ".debug.dylib", "Info.plist"]
            if not all(digest(app / name) == digest(installed / name) for name in names):
                raise AcceptanceError("模拟器实际安装包与候选原件不符")
            root = data / "Documents/review-self-test"
            root.mkdir(parents=True)
            input_path = root / "input.json"
            fd = os.open(input_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as stream:
                json.dump(credential, stream)
            sim_lane.simctl("launch", "--terminate-running-process", dev["udid"], bundle, "--review-self-test", timeout=60)
            deadline = time.monotonic() + 180
            while not (root / "result.json").is_file() and time.monotonic() < deadline:
                time.sleep(.25)
            if not (root / "result.json").is_file():
                raise AcceptanceError("真实 App 未生成审核连接原件")
            shutil.copyfile(root / "result.json", run / "raw.json")
            raw = json.loads((run / "raw.json").read_text())
            checks = raw.get("checks", {})
            if (not REQUIRED.issubset(checks) or any(type(v) is not bool or not v for v in checks.values())):
                raise AcceptanceError("真实 App 审核连接或界面检查未通过；原件：" + str(run / "raw.json"))
            shutil.copyfile(root / "connected.png", run / "connected.png")
            with Image.open(run / "connected.png") as frame:
                colors = frame.convert("RGB").resize((215, 450)).getcolors(215 * 450) or []
                if len(colors) <= 100 or max(n for n, _ in colors) / (215 * 450) >= .97:
                    raise AcceptanceError("真实界面截图为空或缺少控件")
            detail = {"summary": "真实 iOS App 完成独立审核登录、缓存/草稿隔离、云端往返与离屏 Form 渲染",
                      "checks": checks, "observations": raw["observations"], "client_environment": "dedicated iPhone simulator",
                      "service_environment": "real HTTPS independent review instance",
                      "raw_evidence": str(run / "raw.json"), "raw_evidence_sha256": digest(run / "raw.json"),
                      "screenshot": str(run / "connected.png"), "screenshot_sha256": digest(run / "connected.png"),
                      "build_receipt": str(receipt), "build_receipt_sha256": digest(receipt),
                      "installed_candidate_sha256": {name: digest(installed / name) for name in names},
                      "physical_phone_install_verified": False}
            (out / "native_ui.detail.json").write_text(json.dumps(detail, ensure_ascii=False, indent=2) + "\n")
            print(detail["summary"])
            return 0
    finally:
        if input_path:
            input_path.unlink(missing_ok=True)
        if dev["created"]:
            sim_lane.simctl("delete", dev["udid"], check=False)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except sim_lane.Busy as error:
        print("推迟：" + str(error), file=sys.stderr)
        raise SystemExit(75)
    except (AcceptanceError, sim_lane.LaneError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
    except Exception:
        # Fixed diagnostics keep protected JSON and server response bodies out of logs.
        print("原生审核连接验收失败；账号、候选和服务须均就绪，未写通过证据。", file=sys.stderr)
        raise SystemExit(1)
