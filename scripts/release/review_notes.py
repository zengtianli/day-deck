#!/usr/bin/env python3
"""Update this product's Notes/contact with the original ASC API, preserving demo fields."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import asc_listing as listing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    notes = (ROOT / "docs/review-notes-20261016.txt").read_text().strip()
    if not notes or len(notes) > 4000:
        raise RuntimeError("Review Notes为空或超过4000字符，未写入")
    ctx = listing.AppCtx(listing.load_product("day-deck-ios"))
    if ctx.app_id != "6807048407" or ctx.bundle != "cyou.tianli.daydeck":
        raise RuntimeError("ASC产品身份不符，未写入")
    current = listing.get(f"/appStoreVersions/{ctx.version_id}/appStoreReviewDetail").get("data")
    if not current:
        raise RuntimeError("隔离审核账号尚未登记，未写入")
    attrs = current["attributes"]
    protected = ("demoAccountRequired", "demoAccountName", "demoAccountPassword")
    if attrs.get("demoAccountRequired") is not True or not all(attrs.get(k) for k in protected[1:]):
        raise RuntimeError("受保护的专用审核字段不完整，未写入")
    contact = {"contactFirstName": "Tianli", "contactLastName": "Zeng", "contactEmail": "zengtianli1@126.com"}
    if not attrs.get("contactPhone"):
        phone = listing.personal_env("ASC_REVIEW_PHONE")
        contact["contactPhone"] = phone if phone.startswith("+") else "+86" + phone
    update = {"notes": notes, **{k: v for k, v in contact.items() if not attrs.get(k)}}
    changed = any(attrs.get(k) != v for k, v in update.items())
    if args.apply and changed:
        listing.patch(f"/appStoreReviewDetails/{current['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": current["id"], "attributes": update}})
    readback = listing.get(f"/appStoreReviewDetails/{current['id']}")["data"]["attributes"]
    preserved = all(attrs.get(k) == readback.get(k) for k in protected)
    literal_match = readback.get("notes") == notes
    if not preserved or (args.apply and not literal_match):
        raise RuntimeError("ASC审核信息回读不一致，未报告完成")
    record = {"app_id": ctx.app_id, "version_id": ctx.version_id,
              "version": ctx.version["attributes"]["versionString"], "review_detail_id": current["id"],
              "applied": args.apply, "changed": bool(args.apply and changed), "notes_literal_match": literal_match,
              "notes_sha256": hashlib.sha256(notes.encode()).hexdigest(), "notes_characters": len(notes),
              "protected_demo_fields_preserved": preserved, "submitted": False}
    target = ROOT / "build/review-notes-readback-20261016.json"
    target.parent.mkdir(exist_ok=True)
    target.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    if literal_match:
        (target.parent / "review-notes-asc-readback-20261016.txt").write_text(readback["notes"] + "\n")
    print(json.dumps(record, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
