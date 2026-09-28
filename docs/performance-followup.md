# 性能证据接手说明

2026-09-28，只读核对；未采样、构建、启动或安装 App，未修改 `perf/`。本轮收到的空闲门结果为 false（负载 758.8 ≥ 10），不重复等待或绕过。

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

## CLI 下一步

在本仓库执行以下只读命令即可再次定位入口；不要直接运行旧 `sim_perf.py`：

```bash
cd /Users/tianli/Apps/notifhub/ios/01-源程序
~/Dev/.venv/bin/python /Users/tianli/Apps/.claude/skills/app-lightweight/scripts/batch_measure.py day-deck-ios --dry-run
xcrun simctl list devices available --json
~/Dev/.venv/bin/python -c 'import sys; sys.path.insert(0,"/Users/tianli/Apps/chapter/engine"); import app_sop; print(app_sop.steady())'
```

第一条 dry-run 在当前无 `sop.measure` 的情况下预计报告缺配置，不会测量。第三条仅检查接电、用户至少 10 分钟无输入、负载低于核数、没有构建进程；false 时停止，不使用 `--now` 绕过。

本产品已获模拟器安装/启动长期授权。空闲门通过后，接手者应在本仓库新增固定测量入口，复用现有实现而不篡改历史样本：

1. 参考 `/Users/tianli/Library/Logs/app-sop/ios-simulator-20260927b/sim_perf.py` 的 `launch_once()`/`probe()`；把 `DEVICE` 改为显式 `--udid`，由上述 available 列表选定并确认新隔离容器。原 `udid` 文件对应的设备已删除，不能直接使用。
2. 将旧脚本的 `app_sop` import 目录改为 `/Users/tianli/Apps/chapter/engine`。共享采样工具仍为 `/Users/tianli/Apps/.claude/skills/app-lightweight/scripts/measure.py`。
3. 明确本次构建/安装产物，校验安装容器内实际可执行文件 SHA256，并记录真实 `Info.plist`、主机、Runtime 与源码快照。不要根据旧脚本常量固定写 iPhone 17 Pro / iOS 27.0。若使用现有 Release 构建，必须先证明该构建与当前源码绑定。
4. 启动探针沿原方法：丢弃安装后第一次，5 次取中位；从系统日志读取请求启动到首屏 ready，缺任何一次 ready 就保留失败，不能回填旧数。空闲采样启动后静置 45 秒，再对已核对的模拟器 App PID 调用下方共享工具。测量期间不修改被 Chapter 监控的输入。
5. 原始样本先落在临时目录；完成后再一次性落入 `perf/raw/`，用新实测生成 `perf/simulator.json` 的环境、版本、源码/产物 SHA 与原件 SHA，保留本次限制。最后重检该组件性能阶段。

```bash
# 仅在空闲门通过、已有获授权启动且身份核对完成的 PID 后执行；替换 12345。
~/Dev/.venv/bin/python /Users/tianli/Apps/.claude/skills/app-lightweight/scripts/measure.py idle 12345 --seconds 60 > /tmp/day-deck-ios-idle.json
# 新的完整实测证据落盘后，只重检本组件性能阶段。
~/Dev/.venv/bin/python /Users/tianli/Apps/chapter/engine/app_sop.py run --app day-deck-ios --stage perf --check-only
```

该被动 `idle` 命令只量已运行 PID，不能单独生成合格的 iOS 构建/源码绑定，也不能代替首屏速度测量。本轮因空闲门未通过而跳过长采样，装机和启动授权仍有效。
