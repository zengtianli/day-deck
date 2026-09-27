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
| **随手记下，直接保存云端** | 日记和待办状态直接保存云端，iPhone、iPad、Mac 共用数据；草稿留在设备上，离线内容显示更新时间。导出苹果提醒事项才交给 Mac 执行。 |

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
| **2.4 MB**（装好后 3.0 MB） | **28.3 MB** | **0%** | **458 ms** |

体积按具体发行构建回读；真机尚未测量，内存、CPU 与启动时间先用 iOS 模拟器实测并标明环境。

<sub>v0.1 (3) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · TestFlight VALID（未上架）；体积不含用户数据与后续缓存；手机实际安装版本尚未核验 · 2026-09-26。体积来自 Apple App Store Connect 对应构建的设备切片记录。内存、CPU 与启动时间是 iPhone 17 Pro / iOS 27.0 Simulator / Mac16,12 / Apple M4 / macOS 27.2 上本地源码 Release 构建 v0.1 (1) 的实测（2026-09-27），只统计 App 进程，不等于真机数值；真机测量尚未完成。内存口径为 phys_footprint；CPU 为 60 秒采样窗内 CPU 时间 ÷ 墙钟；大小按十进制 MB。原始数据见 [perf/lightweight.json](perf/lightweight.json)。</sub>
<!-- lightweight:end -->
