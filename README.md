**中文** | [English](README_EN.md)

<p align="center"><img src="Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="96" alt="Notihub"></p>

# Notihub · iPhone / iPad

> 2026-09-27 起，原「复盘 / DayDeck」并入 Notihub：与 Notihub Mac 同名同图标、读写同一份云端记录；Mac 端只保留 Notihub。

**早看待办，晚看复盘；在想看的时候打开。**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B-000?logo=apple) ![TestFlight](https://img.shields.io/badge/TestFlight-内测中-0D84FF) ![License](https://img.shields.io/badge/License-MIT-green)

一个安静的日常窗口：看看今天要做什么，记下发生了什么，再回到自己的节奏。

## 它做什么

| 功能 | 说明 |
|---|---|
| **早看要做什么，晚看发生了什么** | 查看逾期、今天与未定时间的待办，按日期翻看复盘和时间线。 |
| **零推送、零角标、零打扰** | 没有推送、通知或角标，想回顾时再打开。 |
| **随手记下，直接保存云端** | 日记和待办状态直接保存云端，iPhone、iPad、Mac 共用数据；草稿留在设备上，离线内容显示更新时间。存进日历仍交给 Mac 执行。 |
| **一键加入提醒事项** | 在「今天」或「通知」页打开一条待办，点「加入提醒事项」，手机直接写进系统提醒事项；有时刻的带到期时间和到点提醒，全天项只带日期。同一条不会重复加入，列表可在「连接」页更换。 |
| **复盘页显示当天提醒（仅本机）** | 「通知」页选中某天时，列出这天到期未完成和这天完成的提醒，由 Notihub 加入的单独标出。只读本机数据，云端不可用时照常显示。 |

## 隐私

- **读取只在本机**：读到的提醒只在内存里显示，不上传、不落盘、不进日志。
- **加入是你主动的操作**：只有点「加入提醒事项」才写入；不会在启动时申请权限，也不会自动加入。
- **备注随你的 iCloud 同步**：加入的提醒备注带待办说明、原文和来源，写进系统提醒事项后随你自己的 iCloud 同步。
- **共享列表成员可见**：如果在「连接」页选的是共享列表，列表成员也能看到加入的内容（含原文）。

系统授权弹窗的说明文案为：「把你选中的待办加入提醒事项，并在复盘页显示当天的提醒。读取的提醒只在本机显示，不会上传。」

去重说明：Notihub 在加入的提醒上留一个标记，据此识别重复。对 Mac 端已推过的待办，还会按「标题相同、到期同一天」查找；这一层依赖 Mac 写入的是 iCloud 列表，「我的 Mac 上」这类本地列表手机看不到，会漏查。

## 怎么拿到

个人专属（内容是本人生活流），不开放安装。

薄壳，读写都走私有后端 `day.tianli.cyou`（访问闸后，内容是作者本人的生活流）。代码可读可编，没有账号跑不出数据。

## 构建

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme DayDeck -destination 'generic/platform=iOS Simulator' build
```

- 仓里的 `*.sh` 是作者本机舰队脚本的 shim（三平台构建 / 真机装机 / TestFlight），依赖 `~/Dev` 下的总部工具，不在本仓；没有那套工具时它们会明确退出。
- `Shared/PlatformCompat.swift` 是总部共享文件的逐字节副本（iOS-only SwiftUI 修饰符在 macOS 侧的同名 no-op），别在这里改它。

开发细节（回归、验证通道、约束）见 [DEVELOPING.md](DEVELOPING.md)。

日常使用、登录、提醒事项授权与离线恢复步骤见 [使用教程](docs/usage-guide.md)。提醒事项功能自 0.2 起提供。

## 相关

- 产品页：<https://apps.tianli.cyou/p/day-deck-ios.html>
- 舰队总览（10 个 app 怎么来的）：<https://apps.tianli.cyou/ios.html>
- 教程：[从零到 TestFlight：一个人做 iPhone app 的完整路径](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 曾田力 (Tianli Zeng)

<!-- lightweight:start -->
## 资源占用

安装包为 App Store 数据；内存、CPU 与启动时间为 iOS 模拟器实测，不是真机数值。

| 安装包 | 空闲内存 | 空闲 CPU | 模拟器冷启动到首屏就绪 |
|---|---|---|---|
| **1.2 MB**（装好后 1.8 MB） | **28.3 MB** | **0%** | **543 ms** |

体积按具体发行构建回读；真机尚未测量，内存、CPU 与启动时间先用 iOS 模拟器实测并标明环境。

<sub>v0.2 (5) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · TestFlight VALID（未上架）；体积不含用户数据与后续缓存；手机实际安装版本尚未核验 · 2026-09-29。体积来自 Apple App Store Connect 对应构建的设备切片记录。内存、CPU 与启动时间是 iPhone 17 Pro / iOS 27.0 Simulator / Mac16,12 / Apple M4 / macOS 27.2 上本地源码 Release 构建 v0.2 (1) 的实测（2026-09-30），只统计 App 进程，不等于真机数值；真机测量尚未完成。内存口径为 phys_footprint；CPU 为 60 秒采样窗内 CPU 时间 ÷ 墙钟；大小按十进制 MB。原始数据见 [perf/lightweight.json](perf/lightweight.json)。</sub>
<!-- lightweight:end -->


## 配置与 App 更新

新构建在主界面下方提供「配置与更新」，显示当前安装包的真实版本和构建号。

当前没有独立可迁移的偏好配置，界面不提供空的 iCloud 开关。账号、访问凭据、业务内容、本机权限与缓存继续使用各自原有入口。

「在 TestFlight 中检查更新」打开系统 TestFlight；内测新包由 TestFlight 安装。 此入口检查 App 版本，资料或后台数据刷新仍在原入口。

版本号更新属于本轮新构建；手机上的新版本需通过签名安装或原商店/TestFlight 渠道取得，发行状态以现有发布记录为准。
