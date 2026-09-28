# 模拟器性能固定入口

2026-09-28，已补 `scripts/measure-simulator.py`。主 agent 于 14:25 实跑 `--check`，返回 75（用户 116 秒前操作，未达 600 秒门槛），没有进入构建、安装、启动或采样，也未修改 `perf/`；不反复等待或绕过，该状态是当次观测。

## 当前结论

现有模拟器测量仍保留原日期与范围，但不能标成当前构建通过。

| 项目 | 现场核对结果 |
| --- | --- |
| 原测量 | `perf/simulator.json`，2026-09-27T14:10:15.343149+08:00，Release 0.1 (1) |
| 原环境 | iPhone 17 Pro / iOS 27.0 Simulator / Mac16,12 / Apple M4 / macOS 27.2；新容器、首次运行数据 |
| 原指标 | 应用进程 footprint 27.0 MiB（28.3 MB）、空闲 CPU 0.0%、首屏中位数 458.2 ms；模拟器 ZIP 1,542,670 B、安装占用 3,952,640 B |
| 原源码绑定 | `f077f9154798bd1c0cfc80b66df97003fbc8d1f633c475a103ffac9886cab953`，git `c1c06ea01594bf3c86cdedf466896ffbdcad9a41` |
| 原测量二进制 SHA256 | `6a6f2959fc67df9166a41e6b63c2a8b5a6fba70b5b2816916abc8c14d0e05c00` |
| 当前 Release 二进制 SHA256 | `1e379ced6b69e8c9418d57c29923fe10737b3f3fb9f069ca0a59392beea2c28c` |
| 当前产物 | `.dd-iphone/Build/Products/Release-iphonesimulator/DayDeck.app/DayDeck`，Info.plist 为 0.1 (1) |
| 原始测量文件校验 | `perf/raw/simulator-full-20260927.json` SHA256 为 `de5a07a8080f40509e25fbc1f09f4cbb7d047ff629871bb6197ec85ec2f5f262`，与证据一致 |

`Sources/API.swift`、`Sources/Gate.swift` 相对原 git 的差异都在 `#if DEBUG` 内；这只能支持 Release 逻辑未因该修复改变，不能把两个不同 SHA256 的二进制认作同一测量产物。未改写 `input_sha256`、测量时间或通过状态。

## Chapter 当前契约

只读核对 `/Users/tianli/Apps/chapter/engine/app_sop.py`：

- `ios_resource_raw()` 读取 `runtime_measurement.simulator` 后，要求 `perf/simulator.json.input_sha256` 与当前 `sop.source`（或 `sop.ui`）快照一致。
- `ios_resource_evidence()` 要求环境、设备、OS、版本、原件及原件 SHA256 有效。
- 当前性能读取路径没有接受 `reused_for`、Release-only 输入或二进制等价证明的复用字段；检索到的 `reused_for` 用于媒体。
- 本组件未登记 `sop.measure`；共享 `batch_measure.py` 不能直接替它执行一套 iOS 模拟器测量，Chapter 自动性能路径也排除 iOS。

因此当前既不满足同件复用，也没有可用的性能复用声明契约。旧数字可作为明确标注日期、模拟器环境的历史结果，不能用于消除当前 budget/speed 缺项。

## CLI 接手

```bash
cd /Users/tianli/Apps/notifhub/ios/01-源程序
# 只读检查：忙时退出 75，不创建目录、设备或修改 perf。
~/Dev/.venv/bin/python scripts/measure-simulator.py --check
# 本轮模拟器构建/安装/启动已获授权；入口仍先检查空闲门。
~/Dev/.venv/bin/python scripts/measure-simulator.py --run
# 新实测成功落盘后，只重检本组件性能阶段。
~/Dev/.venv/bin/python /Users/tianli/Apps/chapter/engine/app_sop.py run --app day-deck-ios --stage perf --check-only
```

空闲门沿用 Chapter `steady()`：接电、用户至少 10 分钟无输入、负载低于核数且没有构建进程。失败退出 75；不循环等待、不自动重试、不提供绕过参数。缺依赖或任一步测量失败退出非零，保留原 `perf/simulator.json`。

默认使用当前可用的最高版本 iOS Runtime 和 `iPhone-17-Pro` 设备类型；可显式指定：

```bash
xcrun simctl list runtimes --json
xcrun simctl list devicetypes --json
~/Dev/.venv/bin/python scripts/measure-simulator.py --run --runtime com.apple.CoreSimulator.SimRuntime.iOS-27-0 --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
```

上述 Runtime 参数是示例，必须以列表返回的可用标识替换。入口每次新建专用模拟器，创建返回值先通过 UUID 校验才进入清理路径；只关闭并删除自己创建的 UUID，shutdown 超时仍尝试 delete。不读取旧 `udid`、不选择真机、不打开 Simulator GUI，也不合成用户输入。

## 实现与验收范围

- Release 构建复用本仓 `bash build-platforms.sh --only iphone --release`；构建前后记录 Chapter 源码快照，真实读取产物 Info.plist 和可执行文件 SHA256，安装后核对安装副本 SHA256。构建后再次检查空闲门，不在繁忙窗口测量。
- 子命令各有独立进程组；超时或中断时先终止该组，5 秒后仍未结束则强制结束，避免构建子孙在失败后继续工作。
- 首屏探针从既有 `/Users/tianli/Library/Logs/app-sop/ios-simulator-20260927b/sim_perf.py` 加载 `log_ts()`、`launch_once()`、`probe()` 三个函数。通过 AST 选择函数定义，避免执行旧模块顶层的已删 UUID 读取与旧 import。缺文件或函数接口改变时明确失败；不复制第二套探针引擎。
- 丢弃安装后第一次启动，后续 5 次全部获得首屏 ready/启动完成时间才取中位数；随后启动 App 静置 45 秒，用共享 `measure.py idle <PID> --seconds 60` 被动采样。内存 `footprint_mb` 的原工具单位是 MiB，CPU 为百分比。
- 在 `build/simulator-perf-*` 临时目录保留本轮启动日志与测量中间物，结束后关闭并删除自己的模拟器。只有清理成功、源码/产物未变、旧 perf 文件没有被别人更新时，才写入新的唯一 `perf/raw/simulator-*.json`，并以原子替换更新 `perf/simulator.json`。原始 JSON 包含逐次日志、样本、运行环境、版本、源码/产物/安装副本/工具 SHA256；摘要引用其 SHA256。不会写 `delivery-evidence.json`。
- 单个文件写回原子化，原件先写、摘要后写；崩溃最多留下未引用原件，不会让摘要引用半个 JSON。构建产物仍由既有入口保存在 `.dd-iphone`，测量临时目录结束后自动清理。
- 主 agent 已统一重跑 10 项隔离测试，其中 6 项覆盖性能入口：空闲门、只读检查、原件摘要与源码/产物绑定、构建失败、无效样本和采样中源码改变；失败均保留旧证据。另 4 项覆盖录制入口。`--check` 实跑返回 75；完整运行及新数字仍待空闲时执行 `--run` 验收，模拟测试和检查成功不等于性能实测通过。
