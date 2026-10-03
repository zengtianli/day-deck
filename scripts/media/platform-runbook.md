# Notihub 单产品串行时段

本文件是待执行入口。只有主 agent 授予时段后执行；本次准备没有构建、模拟器或重测。模拟器拿锁保持显式零等待，首个退出 75 即停止，不排第二条队列。Mac 使用 `notifhub-bar-mac` 已有独立产品；这里不构建 Mac。

2026-10-03 后续仅在原 `store_shots.py` 增加显式 `--in-use`：本人已授权使用中、原canonical串行门仍由Root持有时，iPhone/Vision/Watch可用原headless simctl路线并强制 `--reuse-build`。只跳过闲置600秒；原 `steady(..., allow_owner_now=False)` 的低负载/无构建/非低电量门与明确AC检查保留，初始及每页都核。iPad需要原rotator的cached XCTest，可能触GUI/缓存构建，因此显式in-use返回75，默认仍原闲置路线；没有改固定三capture登记或SDK原回执。以下仅列这次可用的单iPhone实际入口，不重复下方历史SDK准备：

```sh
cd /Users/tianli/Apps/notifhub/ios/01-源程序 && /Users/tianli/Dev/.venv/bin/python -B scripts/media/store_shots.py --platform iphone --reuse-build perf/builds/store-iphone-fixture-20261003.json --in-use
```

本次轻准备未执行该命令。真实成功 `capture.json` 与75/失败stdout均有 `capture_execution`：实际 `command_args`、`in_use`、`user_authorization: explicit --in-use`（仅在显式flag时）、`gate_policy` 及初始/每页的 `gate_observations`，逐项记录原steady实值理由、AC、实际lowpowermode值（探针无此设置时为null）。没有改写 `SOP_OWNER_NOW` / `SOP_SAMPLE_GATE` 或制造父锁。这个helper不写engine attempts/ledger；手动flag结果不能冒称不含flag的fixed-command attempt已当前成功，也不声明业务/性能/上架或完整delivery PASS，Root沿实际调用与原件逐项消费。

2026-10-03 23:56:44 的真实 iPhone 调用首屏结束后，下一页负载 142.5 ≥ 10，原门返回 75，正式 Store 图为 0；原日志 `~/Library/Logs/app-sop/day-deck-ios-capture-iphone-20261003-235644.log` 保留。另核实原 `keep_booted` 接续要求上一调用进程退出，同一 helper PID 连调 `run_sim` 不能接手自己的活 PID 锁。

2026-10-04 轻修复只为 iPhone（含默认模式）和已合格显式 `--in-use` 的 Vision/Watch，沿一个真实原 `sim_lane.Session` 完成一次 boot、一次 install、四次原 baseline/launch/terminate，并复制每次实际返回的 frame；不改默认其他平台/iPad。开机后与每页仍核严格原门，仅负载可在同一 Session 内每 10 秒复探，累计等待最多 180 秒；电源、低电量、其他构建或默认模式用户回归立即 75。原 2400 秒总预算内预留 180 秒清理，原 Session 自动 shutdown/release 自己的锁，禁止手删 foreign 锁。新增 `stabilization` 记录实际累计等待，`native_session.cleanup_completed` 只表示原退出接口已正常返回，不冒称已验证 shutdown；每页 `lane_result.shutdown: false` 如实表示拍该页时同一设备继续开着，实际清理在四页后或中途退出发生。这轮没有重新执行截图。

当前 47 个平台源输入为 `3c63c9933477df5eb433c95e425e87c21ba55328f3a605df9b2b58c62149e6e9`。原 Claude `builds/iphone.json`、`builds/vision.json` 已证实源输入一致，但二者都是 Debug，不能冒充原样 Release。其现有包可直接供截图入口 `--reuse-build` 使用，不需再次构建。原 `builds/watch-release.json` 是已知原样 Release 候选，尚未完成共享严格复用校验；只在时段内通过 `--reuse-build` 校验成功才算可复用，否则使用下述新 iPhone 包内实际 Watch 产物。

## 最少新构建

需要 iPhone 和 Vision 各一次原样 Release、各一次 Release `-O` + `DEBUG` 合成运行包，共四次构建。iPad 直接使用 iPhone 包；iPhone 会嵌入 Watch，所以优先派生实际 Watch 回执，不单独重复编译 Watch。若实际未嵌入才单独构建缺失的 Watch 配置。

从源目录执行，先固定一个仓外持久目录，后续重入使用同一目录：

```bash
cd /Users/tianli/Apps/notifhub/ios/01-源程序
export NOTIHUB_LANE_WORK=/private/tmp/notihub-platforms-3c63c993
python3 scripts/media/build_receipts.py --platform iphone --out "$NOTIHUB_LANE_WORK"
python3 scripts/media/build_receipts.py --platform iphone --fixture-debug --out "$NOTIHUB_LANE_WORK"
python3 scripts/media/build_receipts.py --platform watch --out "$NOTIHUB_LANE_WORK" --from-iphone "$NOTIHUB_LANE_WORK/iphone-release.json"
python3 scripts/media/build_receipts.py --platform watch --fixture-debug --out "$NOTIHUB_LANE_WORK" --from-iphone "$NOTIHUB_LANE_WORK/iphone-fixture.json"
```

现存回执会调用共享 `reuse_build`，核对当前源码副本、编译条件、SDK、Xcode、包版本和实际二进制；校验失败停止，不能自动重建来掩盖失败。保留仓外产物供下面所有阶段复用。四条移动线按 iPhone → iPad → Watch → Vision 串行。

## 性能、启动与截图共用一包

每条线均由共享测量器读取原样 Release 包体、隔离优化包的运行值；启动时间已包含在这次真实性能采样中，不另跑一轮启动测试。

```bash
python3 /Users/tianli/Apps/.claude/skills/app-lightweight/scripts/platform_measure.py --app day-deck-ios --repo . --platform iphone --fixture-debug --sync-ios --reuse-size-build "$NOTIHUB_LANE_WORK/iphone-release.json" --reuse-runtime-build "$NOTIHUB_LANE_WORK/iphone-fixture.json" --lock-wait 0 --load-wait 0
python3 scripts/media/store_shots.py --platform iphone --reuse-build "$NOTIHUB_LANE_WORK/iphone-fixture.json"
python3 /Users/tianli/Apps/.claude/skills/app-lightweight/scripts/platform_measure.py --app day-deck-ios --repo . --platform ipad --fixture-debug --sync-ios --reuse-size-build "$NOTIHUB_LANE_WORK/iphone-release.json" --reuse-runtime-build "$NOTIHUB_LANE_WORK/iphone-fixture.json" --lock-wait 0 --load-wait 0
python3 scripts/media/store_shots.py --platform ipad --reuse-build "$NOTIHUB_LANE_WORK/iphone-fixture.json"
python3 /Users/tianli/Apps/.claude/skills/app-lightweight/scripts/platform_measure.py --app day-deck-ios --repo . --platform watch --fixture-debug --sync-ios --reuse-size-build "$NOTIHUB_LANE_WORK/watch-release.json" --reuse-runtime-build "$NOTIHUB_LANE_WORK/watch-fixture.json" --lock-wait 0 --load-wait 0
python3 scripts/media/build_receipts.py --platform vision --out "$NOTIHUB_LANE_WORK"
python3 scripts/media/build_receipts.py --platform vision --fixture-debug --out "$NOTIHUB_LANE_WORK"
python3 /Users/tianli/Apps/.claude/skills/app-lightweight/scripts/platform_measure.py --app day-deck-ios --repo . --platform vision --fixture-debug --sync-ios --reuse-size-build "$NOTIHUB_LANE_WORK/vision-release.json" --reuse-runtime-build "$NOTIHUB_LANE_WORK/vision-fixture.json" --lock-wait 0 --load-wait 0
python3 scripts/media/store_shots.py --platform vision --reuse-build "$NOTIHUB_LANE_WORK/vision-fixture.json"
```

首次未测的四条性能线需要采样。重入前使用共享 `platform_measure.current_evidence` 判据；其会校验当前输入、真实原始证据文件及 SHA、平台与运行包 DEBUG 条件。有效同输入证据跳过，不能仅见摘要便重测或算通过。

Notihub compact 原件及原 summary 已通过、源码输入已核匹配，直接复用 `shots/proof/compact-unchanged`，不再跑 compact。Watch 四张已有静态来源/规格/视觉核验，实际 Watch/Widget 编译输入未变，复用 `shots/appstore/watch`，不重复拍图。其回执明确只有静态源绑定，不冒称本轮新二进制采样。iPhone 商店尺寸、iPad 横屏与 Vision 最终图仍需要上面的截图步骤，截图完成后做实际视觉审查；机器规格成功不等于视觉通过。

## 三项业务验收

现有 `scripts/accept/functionality.sh` 调用 `FunctionalityAcceptanceTests`；`recovery.sh` 调用 `RecoveryAcceptanceTests` 和三项离线、旧缓存、请求取消 CloudContractTests；`privacy.sh` 调用 `PrivacyAcceptanceTests`。各自 `_common.sh` 运行 `xcrun swift test -j 2 --filter` 并要求至少执行一项且零失败。只覆盖生产核心隔离模拟网络/临时缓存，不覆盖真机、线上服务或真实 Keychain。

旧正式业务回执绑定已经过期，不能改 hash 伪装通过。本轮已有同源 45 tests 零失败；主 agent 优先按治理确认能否导入真实已有证据，缺少可导入原始证据时才执行登记的三项 runner，不能再全量测试。

```bash
python3 /Users/tianli/Apps/chapter/engine/app_sop.py accept --app day-deck-ios --check functionality --check recovery --check privacy --json
```

最后由主 agent 汇总到唯一全平台交接。这里不执行推送、发版、部署或装机。
