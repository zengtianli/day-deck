<p align="center"><img src="Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="96" alt="每日复盘"></p>

# 每日复盘 · day-deck

**早看待办，晚看复盘；在想看的时候打开。**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) ![TestFlight](https://img.shields.io/badge/TestFlight-内测中-0D84FF) ![License](https://img.shields.io/badge/License-MIT-green)

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
