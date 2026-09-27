# Notihub iOS 推广页缺项交接

本轮仅调查并保存本文，未修改共享配置、Mac 仓、门户或共享引擎，未部署。时间：2026-09-28。

## 已核实的责任层

`~/Dev/tools/configs/menus/entities/products.yaml` 把 `day-deck-ios` 的主页登记为 `https://app-mac-notihub.tianli.cyou/#iphone`，正式图标登记为本仓 `Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`。本仓 `make_icon.py` 从 Mac 同源图裁出满幅、不透明 iOS 图标；Mac 行登记的是 `~/Apps/notifhub/mac/icon/AppIcon.icns`，存在平台包装差异。

`~/Dev/tools/dev/lib/tools/macapp/product_icons.py` 的 `IconReferences` 不处理 URL fragment。`~/Apps/chapter/engine/app_sop.py` 对产品主页调用它时传 `product_id=None`，于是 `#iphone` 仍会收集整页品牌图标和 favicon，再逐个与 iOS 正式素材比较。Chapter 开工前报告的差值是 21.59/255；本轮核实了错误比较范围的源码，没有把它视为 iOS 图标需要重新设计的证据。

`~/Apps/apps-portal/site/standalone_homepage.py` 的 `companions()` 能识别 `#iphone` 所属的 iOS 组件，但目前渲染 companion section 时只输出截图、文案、功能及获取说明，没有输出它的正式图标或 `perf_block.section(sibling['_perf'])`。父级 Mac 性能卡不能证明 iOS 性能。

最小修复需同时在两处落实：

1. 门户 `standalone_homepage.py` 的 companion section 输出该组件 `_icon` 和 `_perf`，标明 iPhone/iPad 与测量环境，继续保持自用展示、无公开下载。
2. 共享 `product_icons.py` 对带 fragment 的主页只检查目标 section 内的可见组件图标；不存在 section 或可见图标时失败。全页主页继续核对全页品牌/favicon，不能降低像素阈值掩盖错误，也不能用改变 iOS 正式源规避。

这两处均在本组件仓外，修改前须声明共享范围。本轮保留了责任层与修改步骤；线上 `page_icon` 和 `page` 需重建部署后回读，而本轮明确禁止部署。

## 性能事实

`perf/simulator.json` 是 2026-09-27 的 `0.1 (1)` Release 模拟器记录：空闲 27 MiB（28.3 MB）、0% CPU、首屏 458.2 ms；其 ZIP 不是 App Store IPA。此文件保留来源哈希和原始测量路径。当前生产源码已改变，不能直接将这些数值标为本轮有效结果。

本轮主 agent 已确认空闲门失败（负载 95.6，要求低于 10），因此跳过重新采样，不等待长时间空闲、不反复尝试。页面展示的安装包/安装后占用也应继续由当前 `perf/lightweight.json` 及测量管线派生，不能手填本文中的历史数字。

## 在本仓 CLI 接手

先执行安全的状态复核；`--check-only` 必须保留。`app_sop.py run` 的真实帮助说明其默认可能自动修复、推送和部署，不能在本轮边界下裸跑。

```bash
cd /Users/tianli/Apps/notifhub/ios/01-源程序
~/Dev/.venv/bin/python /Users/tianli/Apps/chapter/engine/app_sop.py run --app day-deck-ios --check-only --json
```

接续共享修复时，先检查并声明两处范围，再按上文修改；以下命令本轮未执行。

```bash
python3 ~/Dev/tools/cc-home/tools/harness/claims.py list
python3 ~/Dev/tools/cc-home/tools/harness/claims.py claim --owner 'Notihub iOS 共享主页修复' ~/Apps/apps-portal/site ~/Dev/tools/dev/lib/tools/macapp/product_icons.py
${EDITOR:-vi} ~/Apps/apps-portal/site/standalone_homepage.py ~/Dev/tools/dev/lib/tools/macapp/product_icons.py
~/Dev/.venv/bin/python ~/Apps/apps-portal/site/gen_site.py
```

性能重新采样须先有设备运行条件，并满足空闲门。当前没有登记 `sop.measure`，`run --stage perf` 不能自动补测。先用 CLI 确认空闲门；失败即停止，不等待或重试：

```bash
~/Dev/.venv/bin/python - <<'PY'
import sys
sys.path.insert(0, '/Users/tianli/Apps/chapter/engine')
import app_sop
ok, reason = app_sop.steady()
print(reason)
raise SystemExit(0 if ok else 1)
PY
```

门通过且本人允许模拟器装机后，按 [录制说明](demo-recording.md) 创建专用模拟器（变量 `DEMO_SIM_UDID`），以本轮构建的 Release 包替换其中的 Debug 包，再采集 App 进程；以下有装机动作，本轮未执行：

```bash
xcrun simctl install "$DEMO_SIM_UDID" .dd-iphone/Build/Products/Release-iphonesimulator/DayDeck.app
PERF_APP_PID="$(xcrun simctl launch --terminate-running-process "$DEMO_SIM_UDID" cyou.tianli.daydeck | awk '{print $NF}')"
sleep 45
~/Dev/.venv/bin/python ~/Apps/.claude/skills/app-lightweight/scripts/measure.py idle "$PERF_APP_PID" --seconds 60 > build/simulator-idle.json
xcrun simctl shutdown "$DEMO_SIM_UDID"
```

此命令只生成内存/CPU 原始采样，不能证明启动速度或完整通过。还需复用旧首屏计时流程并绑定实际构建/系统/源码哈希到 `perf/simulator.json`；旧流程保存在 `~/Library/Logs/app-sop/ios-simulator-20260927b/sim_perf.py`，其中固定的模拟器 UUID 已失效、旧引擎 import 路径已迁移，必须先适配，不能原样运行。此复用适配留待性能后续，不在本轮开展长采样。

发布入口已从源码核实为 `~/Apps/apps-portal/site/deploy.sh`。当前 Notihub 行未配置 `homepage_bundle`，因此 `--products-only` 的专用发布器会拒绝此产品，不能套用该参数声称只发布 Notihub。现有标准入口会重建、同步整个门户并处理 nginx；只有另行授权该部署范围、确认共享修改和产物后才运行：

```bash
bash ~/Apps/apps-portal/site/deploy.sh
~/Dev/.venv/bin/python /Users/tianli/Apps/chapter/engine/app_sop.py run --app day-deck-ios --check-only --json
```

最后一次检查将由现有引擎回读真实线上图片和页面数字。本文不是图标、页面、性能或播放通过证据，不手写 `perf/delivery-evidence.json`。
