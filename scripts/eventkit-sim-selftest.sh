#!/bin/bash
# 模拟器 EventKit 自检：在一台本次新建的专用 iPhone 模拟器里装 Debug 包，授予提醒事项权限，
# 以 `-reminderSelfTest st.json` 启动 App（Sources/ReminderSelfTest.swift），读回 App 容器
# Documents/st.json 判定 ok==true 且 dedup_ms<=500。
#
# 非交互、不合成任何点击或按键；只删除本次新建的那台模拟器（按 UUID）。
# 退出：0 通过 / 75 有别的构建在跑（未构建、未建模拟器）/ 78 没有可用的 iOS runtime 或 iPhone 设备类型
#       / 其他非零 = 构建、安装、运行或判定失败。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUNDLE=cyou.tianli.daydeck
RESULT=st.json
RUN_TIMEOUT="${SELFTEST_TIMEOUT:-120}"
BOOT_TIMEOUT="${SIM_BOOT_TIMEOUT:-240}"

# ── 并发门：这是短时功能自检（后台模拟器，不抢鼠标键盘焦点），不需要性能采样的用户空闲门；
#    只在别的构建正在跑时退出，免得两个 xcodebuild 抢同一份 DerivedData。
if pgrep -x xcodebuild >/dev/null; then
  echo "BLOCKED: 有别的 xcodebuild 在跑；未构建、未建模拟器" >&2
  exit 75
fi

# shellcheck disable=SC1091
source "$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh"
xcode_env_use iphonesimulator >/dev/null || { echo "没有带 iOS 模拟器 SDK 的 Xcode" >&2; exit 78; }

# ── 选 runtime 与 iPhone 设备类型（最新可用 runtime；优先 iPhone 17 Pro）──────
PICK=$(python3 - <<'PY' || true
import json, re, subprocess
rt = json.loads(subprocess.run(["xcrun", "simctl", "list", "runtimes", "--json"], capture_output=True, text=True, check=True).stdout)["runtimes"]
rt = [r for r in rt if r.get("isAvailable") and ".iOS-" in r["identifier"]]
if not rt:
    raise SystemExit(1)
runtime = max(rt, key=lambda r: tuple(int(n) for n in re.findall(r"\d+", r["version"])))
types = [t["identifier"] for t in runtime.get("supportedDeviceTypes", []) if "iPhone" in t.get("name", "")]
if not types:
    types = [t["identifier"] for t in json.loads(subprocess.run(["xcrun", "simctl", "list", "devicetypes", "--json"],
             capture_output=True, text=True, check=True).stdout)["devicetypes"] if "iPhone" in t["name"]]
if not types:
    raise SystemExit(1)
preferred = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
print(runtime["identifier"], preferred if preferred in types else types[-1])
PY
)
if [ -z "$PICK" ]; then
  echo "没有可用的 iOS 模拟器 runtime 或 iPhone 设备类型" >&2
  exit 78
fi
RUNTIME=${PICK% *}
DEVTYPE=${PICK#* }

# ── 新建专用模拟器；trap 只清理这台（UUID 限定）─────────────────────────────
NAME="Notihub-selftest-iPhone-$(uuidgen | tr -d - | cut -c1-12 | tr 'A-Z' 'a-z')"
UDID=""
WORK=$(mktemp -d "${TMPDIR:-/tmp}/notihub-selftest.XXXXXX")
LAUNCH_PID=""
cleanup() {
  local rc=$?
  if [ -n "$LAUNCH_PID" ] && kill -0 "$LAUNCH_PID" 2>/dev/null; then kill "$LAUNCH_PID" 2>/dev/null || true; fi
  if [ -n "$UDID" ]; then
    xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
    xcrun simctl delete "$UDID" >/dev/null 2>&1 || echo "清理：删除模拟器 $UDID 失败" >&2
  fi
  rm -rf "$WORK"
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

CREATED=$(xcrun simctl create "$NAME" "$DEVTYPE" "$RUNTIME" 2>"$WORK/create.err") || {
  echo "新建模拟器失败（$DEVTYPE / $RUNTIME）：$(cat "$WORK/create.err")" >&2
  exit 78
}
# 只接受真实 UUID，拒绝 booted 之类别名进入清理。
if ! [[ "$CREATED" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "simctl create 没有返回 UUID：$CREATED" >&2
  exit 1
fi
UDID=$(printf '%s' "$CREATED" | tr 'a-f' 'A-F')
echo "专用模拟器：$NAME ($UDID) · ${RUNTIME##*.} · ${DEVTYPE##*.}"

# ── 构建并安装 Debug 包（共享 sim-run.sh；环境只留必要变量，凭证不进构建产物）──
echo "构建 Debug 并安装（sim-run.sh --no-shot --shutdown）"
if ! env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
     SHELL="${SHELL:-/bin/bash}" LANG="${LANG:-en_US.UTF-8}" ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} \
     SIM_NAME="$NAME" SIM_LAUNCH_ARGS="-demo 1" \
     bash sim-run.sh --no-shot --shutdown >"$WORK/build.log" 2>&1; then
  tail -30 "$WORK/build.log" >&2
  echo "构建/安装失败" >&2
  exit 1
fi
grep -F "$NAME" "$WORK/build.log" >/dev/null || { tail -20 "$WORK/build.log" >&2; echo "sim-run.sh 没有用到本次新建的模拟器" >&2; exit 1; }

# ── 开机（有上限）────────────────────────────────────────────────────────────
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 &
BOOT_PID=$!
WAITED=0
while kill -0 "$BOOT_PID" 2>/dev/null; do
  if [ "$WAITED" -ge "$BOOT_TIMEOUT" ]; then
    kill "$BOOT_PID" 2>/dev/null || true
    echo "模拟器 ${BOOT_TIMEOUT}s 内没开完机" >&2
    exit 1
  fi
  sleep 2; WAITED=$((WAITED + 2))
done
wait "$BOOT_PID" || { echo "模拟器开机失败" >&2; exit 1; }

# ── 确认装的是 Debug 包（Xcode Debug 构建把代码放进 <名>.debug.dylib）──────────
APP_PATH=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Info.plist")
[ -f "$APP_PATH/$EXE.debug.dylib" ] || { echo "已装包不是 Debug（缺 $EXE.debug.dylib）" >&2; exit 1; }
grep -q "reminderSelfTest" "$APP_PATH/$EXE.debug.dylib" \
  || { echo "已装 Debug 包里没有 reminderSelfTest 入口字符串" >&2; exit 1; }
echo "已装 Debug 包：$EXE.debug.dylib"

# ── 授权 + 运行自检 ──────────────────────────────────────────────────────────
xcrun simctl privacy "$UDID" grant reminders "$BUNDLE"
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
rm -f "$DATA/Documents/$RESULT"

echo "启动自检（最多 ${RUN_TIMEOUT}s）"
xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE" \
  -reminderSelfTest "$RESULT" </dev/null >"$WORK/console.log" 2>&1 &
LAUNCH_PID=$!
WAITED=0
while kill -0 "$LAUNCH_PID" 2>/dev/null; do
  if [ "$WAITED" -ge "$RUN_TIMEOUT" ]; then
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    echo "自检 ${RUN_TIMEOUT}s 内没有退出；控制台末尾：" >&2
    tail -20 "$WORK/console.log" >&2
    exit 1
  fi
  sleep 1; WAITED=$((WAITED + 1))
done
wait "$LAUNCH_PID" || true
LAUNCH_PID=""
echo "App 已退出（${WAITED}s）；控制台："
grep -v '^$' "$WORK/console.log" | tail -10 || true

# ── 读结果并判定 ─────────────────────────────────────────────────────────────
OUT="$DATA/Documents/$RESULT"
[ -f "$OUT" ] || { echo "没有生成 Documents/$RESULT（App 可能未调用 ReminderSelfTest.runIfRequested）" >&2; exit 1; }
echo "── Documents/$RESULT ──"
cat "$OUT"
echo
python3 - "$OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ms = d.get("dedup_ms", -1)
ok = d.get("ok") is True and isinstance(ms, (int, float)) and 0 <= ms <= 500
print(("PASS" if ok else "FAIL") + f": ok={d.get('ok')} dedup_ms={ms} url_readback={d.get('url_readback')} failures={d.get('failures')}")
sys.exit(0 if ok else 1)
PY
