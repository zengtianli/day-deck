#!/bin/bash
# MarkdownView 同源件的责任源：本仓（day-deck）的 Sources/MarkdownView.swift。
# 2026-09-17 起由 day-deck 持有；此前的源 blog-reader 已退役，更早出自 ask-claude。
# 其他 App vendored 复用；只容许 import SwiftUI 前的 // 注释/空行不同。
# 默认消费者按「各产品族并排放在同一个根目录下」的布局解析（见 CONSUMERS）；
# 布局不同就用 --targets 显式给。消费者缺失或集合为空一律失败，不报绿。
# 默认检查全部消费者；--app 供本机构建预检选当前消费者，源项目仍检查全部。
# --sync 显式更新实现并保留消费者前言、留下原件备份；不创建缺失源或消费者。
set -euo pipefail
MARKDOWN_ROOT="$(cd "$(dirname "$0")" && pwd)"
python3 - "$MARKDOWN_ROOT" "$@" <<'PY'
import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time

root = Path(__import__("sys").argv[1]).resolve()
parser = argparse.ArgumentParser(description="Check the current Markdown renderer and its declared vendored consumers")
parser.add_argument("--source", type=Path, default=root / "Sources/MarkdownView.swift")
parser.add_argument("--targets", type=Path, nargs="*", help="Explicit replacement for the default consumer set (empty fails)")
parser.add_argument("--app", type=Path, help="Build scope: app container or source directory")
parser.add_argument("--sync", action="store_true", help="Copy source implementation, preserving reviewed consumer headers")
args = parser.parse_args(__import__("sys").argv[2:])
source = args.source.expanduser().resolve()
# root = <apps>/notifhub/ios/01-源程序 → root.parents[2] = <apps>
CONSUMERS = ("hydro-assistant/ios",)  # hydro-deck（options-desk 已于 2026-09-17 退役）
SOURCE_MARK = "day-deck"  # 消费者前言里声明出处的标记；--app 靠它识别未登记的消费者
defaults = [root.parents[2] / name / "01-源程序/Sources/MarkdownView.swift" for name in CONSUMERS]
targets = defaults if args.targets is None else args.targets
if args.app:
    app = args.app.expanduser().resolve()
    if (app / "01-源程序/project.yml").is_file():
        app = app / "01-源程序"
    target = app / "Sources/MarkdownView.swift"
    if app != source.parent.parent:
        header = target.read_text().split("import SwiftUI", 1)[0] if target.is_file() else ""
        if target not in defaults and SOURCE_MARK not in header:
            print(json.dumps({"result": "NOT_APPLICABLE", "app": str(app), "reason": "No declared Markdown renderer consumer"}))
            raise SystemExit(0)
        targets = [target]


def split_renderer(filename):
    raw = filename.read_bytes()
    lines = raw.splitlines(keepends=True)
    prefix = []
    for index, line in enumerate(lines):
        if line.rstrip(b"\r\n") == b"import SwiftUI":
            return raw, b"".join(prefix), b"".join(lines[index:])
        if line.strip() and not line.lstrip().startswith(b"//"):
            raise ValueError("Non-comment content before import SwiftUI: " + str(filename))
        prefix.append(line)
    raise ValueError("Missing renderer import boundary: " + str(filename))


try:
    if not targets:
        raise ValueError("Empty consumer scope; no renderer consumers checked")
    targets = [target.expanduser().resolve() for target in targets]
    if source in targets or len(set(targets)) != len(targets):
        raise ValueError("Consumer scope contains the source itself or duplicate consumers")
    original, _, body = split_renderer(source)
    planned, entries = [], []
    # Validate every input before any requested copy; missing target is never silently created.
    for target in targets:
        before, prefix, current = split_renderer(target)
        same = current == body
        entries.append({"target": str(target), "result": "synced" if same else "drifted"})
        if not same:
            planned.append((target, before, prefix + body))
    if args.sync:
        for target, before, content in planned:
            if source.read_bytes() != original or target.read_bytes() != before:
                raise ValueError("Source or consumer changed after planning: " + str(target))
            backup = target.with_name(target.name + ".before-sync-" + str(time.time_ns()))
            backup.write_bytes(before)
            descriptor, temporary = tempfile.mkstemp(prefix=".markdown-sync-", dir=target.parent)
            try:
                with os.fdopen(descriptor, "wb") as stream:
                    stream.write(content)
                os.chmod(temporary, target.stat().st_mode & 0o777)
                os.replace(temporary, target)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
            next(row for row in entries if row["target"] == str(target)).update(result="applied", backup=str(backup))
    bad = sum(row["result"] == "drifted" for row in entries)
    print(json.dumps({"result": "FAIL" if bad else "PASS", "source": str(source),
                      "source_body_sha256": hashlib.sha256(body).hexdigest(), "consumers": len(entries), "entries": entries}, ensure_ascii=False))
    raise SystemExit(1 if bad else 0)
except (OSError, ValueError) as error:
    print(json.dumps({"result": "FAIL", "error": str(error)}, ensure_ascii=False))
    raise SystemExit(2)
PY
