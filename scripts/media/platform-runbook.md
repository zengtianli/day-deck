# Notihub 单产品串行时段

本文件是待执行入口。只有主 agent 授予时段后执行；本次准备没有构建、模拟器或重测。所有模拟器步骤显式零等待，首个退出 75 即停止，不排第二条队列。Mac 使用 `notifhub-bar-mac` 已有独立产品；这里不构建 Mac。

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
