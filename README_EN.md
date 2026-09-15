[中文](README.md) | **English**

<p align="center"><img src="Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="96" alt="Daily Review"></p>

# Daily Review · day-deck



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

## Related

- Product page: <https://apps.tianli.cyou/p/day-deck-ios.html>
- Fleet overview (how the 10 apps came about): <https://apps.tianli.cyou/ios.html>
- Tutorial: [From zero to TestFlight: the complete path to building iPhone apps solo](https://blog-ai.tianli.cyou/nine-ios-apps-in-two-weeks)

## License

MIT © 2026 Tianli Zeng
