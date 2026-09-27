#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"
accept_scope 'functionality: 本机生产核心隔离集成；合成网络响应及独立临时缓存，执行 API/Store/Writer 真实路径。覆盖今日待办分组、长摘要/正文、日记回执及失效回读、状态回读、提醒事项排队。未覆盖 iOS 界面、真机或线上服务。'
accept_swift_tests FunctionalityAcceptanceTests
