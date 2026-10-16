#!/usr/bin/env python3
"""Apply/read back this product's editable store text using the original ASC API.

Intentionally leaves URLs, age declarations, demo credentials, builds and submission
untouched: the current policy/support pages have not been successfully published.
"""
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
    ctx = listing.AppCtx(listing.load_product("day-deck-ios"))
    if ctx.app_id != "6807048407" or ctx.bundle != "cyou.tianli.daydeck":
        raise RuntimeError("ASC 产品身份不符，未写入")
    st = ctx.r["store"]
    info = ctx.info_loc(create=args.apply)
    version = ctx.version_loc(create=args.apply)
    if not info or not version:
        raise RuntimeError("本地化尚未创建；用 --apply 沿原 ASC 入口创建")
    desired = (
        ("appInfoLocalizations", info, {"name": st["display_name"], "subtitle": st["subtitle"]}),
        ("appStoreVersionLocalizations", version,
         {"description": st["description"].strip(), "keywords": st["keywords"].strip()}),
        ("appStoreVersions", ctx.version, {"copyright": st["copyright"]}),
    )
    if len(st["subtitle"]) > 30 or len(st["description"].strip()) > 4000 or len(st["keywords"].strip()) > 100:
        raise RuntimeError("商店文字超过 ASC 限制，未写入")
    changes, matches = [], {}
    for kind, current, wanted in desired:
        diff = {key: value for key, value in wanted.items() if current["attributes"].get(key) != value}
        if args.apply and diff:
            listing.patch(f"/{kind}/{current['id']}", {"data": {
                "type": kind, "id": current["id"], "attributes": diff}})
            changes.extend(kind + "." + key for key in diff)
        actual = listing.get(f"/{kind}/{current['id']}")["data"]["attributes"]
        matches.update({kind + "." + key: actual.get(key) == value for key, value in wanted.items()})
    category = {"data": {"type": "appCategories", "id": st["category"]}}
    endpoint = f"/appInfos/{ctx.info['id']}/relationships/primaryCategory"
    if listing.get(endpoint).get("data") != category["data"] and args.apply:
        listing.patch(f"/appInfos/{ctx.info['id']}", {"data": {
            "type": "appInfos", "id": ctx.info["id"], "relationships": {"primaryCategory": category}}})
        changes.append("appInfos.primaryCategory")
    matches["appInfos.primaryCategory"] = listing.get(endpoint).get("data") == category["data"]
    record = {"app_id": ctx.app_id, "version_id": ctx.version_id,
              "applied": args.apply, "changed_fields": changes, "literal_matches": matches,
              "description_sha256": hashlib.sha256(st["description"].strip().encode()).hexdigest(),
              "urls_untouched": True, "demo_fields_untouched": True,
              "build_untouched": True, "submitted": False}
    output = ROOT / "build/store-metadata-readback-20261016.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(record, ensure_ascii=False))
    if args.apply and not all(matches.values()):
        raise RuntimeError("ASC 商店文字回读不一致，未报告完成")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
