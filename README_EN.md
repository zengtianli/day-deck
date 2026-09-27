[中文](README.md) | **English**

<p align="center"><img src="Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="96" alt="Notihub"></p>

# Notihub · iPhone / iPad

> Since 2026-09-27 the former Daily Review / DayDeck app is part of Notihub: same name and icon as Notihub for Mac, reading and writing the same cloud records. On the Mac only Notihub remains.



**Tasks in the morning, reflection in the evening; open it when you want to.**

![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-0D84FF?logo=swift&logoColor=white) ![Platform](https://img.shields.io/badge/iOS%2018.0%2B%20·%20macOS%2015.0%2B-000?logo=apple) ![TestFlight](https://img.shields.io/badge/TestFlight-内测中-0D84FF) ![License](https://img.shields.io/badge/License-MIT-green)

A quiet daily window: see what needs doing today, record what happened, then return to your own rhythm.

## What it does

| Feature | Description |
|---|---|
| **See what to do in the morning and what happened in the evening** | View overdue, today's, and unscheduled tasks; browse reviews and timelines by date. |
| **No push notifications, badges, or interruptions** | No pushes, notifications, or badges; open it when you want to look back. |
| **Write a quick note and save directly to the cloud** | Journals and task status save directly to the cloud, sharing data across iPhone, iPad, and Mac. Drafts stay on the device, and offline content shows its last update time. Only export to Apple Reminders is delegated to the Mac. |

## Availability

For personal use only: the content is the author's own daily activity stream, and installation is not open to others.

A thin shell whose reads and writes use the private backend `day.tianli.cyou` (behind access control, containing the author's own daily activity stream). The code can be read and built, but no data is available without an account.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme DayDeck -destination 'generic/platform=iOS Simulator' build
```

- The repository's `*.sh` files are shims for the author's local fleet scripts (three-platform builds / device installation / TestFlight). They depend on HQ tools under `~/Dev` that are not in this repository; without them, the scripts exit explicitly.
- `Shared/PlatformCompat.swift` is a byte-for-byte copy of a shared HQ file (iOS-only SwiftUI modifiers become same-named no-ops on macOS). Do not edit it here.

See [DEVELOPING.md](DEVELOPING.md) for development details, including regression checks, validation channels, and constraints.

See the [usage and recovery guide (Chinese)](docs/usage-guide.md) for everyday use, login, and offline recovery.

## Related

- Product page: <https://apps.tianli.cyou/p/day-deck-ios.html>
- Fleet overview (how the 10 apps came about): <https://apps.tianli.cyou/ios.html>
- Tutorial: [From zero to TestFlight: the complete path to building iPhone apps solo](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 Tianli Zeng

<!-- lightweight:start -->
## Resource use

The simulator figures below are historical measurements of the 2026-09-27 build. Current source performance still needs measurement. Package sizes remain tied to the listed ASC build.

Download size is App Store data; memory, CPU and launch time are iOS Simulator measurements, not physical-device figures.

| Download | Idle memory | Idle CPU | Simulator cold launch to first screen ready |
|---|---|---|---|
| **2.4 MB** (installed 3.0 MB) | **28.3 MB** | **0%** | **458 ms** |

Sizes are read back for this exact distribution build. The physical device is not yet measured, so memory, CPU and launch time come from the iOS Simulator and are labelled as such.

<sub>v0.1 (3) · iPhone 17（iPhone18,3）；体积为 Apple 设备切片记录，运行性能尚未真机实测 · TestFlight VALID（未上架）; package sizes exclude user data and caches; installed phone version not verified · measured 2026-09-26. Sizes come from Apple App Store Connect device slices for this build. Memory, CPU and launch time were measured on iPhone 17 Pro / iOS 27.0 Simulator / Mac16,12 / Apple M4 / macOS 27.2 with a local Release build v0.1 (1) (2026-09-27), App process only; these are not physical-device figures, which are still unmeasured. Memory uses phys_footprint; CPU is CPU time ÷ wall time over a 60-second sampling window; sizes in decimal MB. Raw data: [perf/lightweight.json](perf/lightweight.json).</sub>
<!-- lightweight:end -->
