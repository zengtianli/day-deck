// swift-tools-version: 5.9
import PackageDescription

// Tests compile these exact production files; the app remains built by its Xcode project.
let package = Package(
    name: "DayDeckCore",
    platforms: [.macOS("15.0")],
    products: [.library(name: "DayDeckCore", targets: ["DayDeckCore"])],
    targets: [
        .target(name: "DayDeckCore", path: "Sources",
                exclude: ["App.swift", "TodayView.swift", "MarkdownView.swift", "DiaryView.swift", "RecapView.swift",
                         "ReminderViews.swift", "ReminderSelfTest.swift", "Adaptive.swift", "RegularRootView.swift",
                         "WatchLink.swift", "Palette.swift"],
                sources: ["API.swift", "Models.swift", "Store.swift", "Gate.swift", "Writer.swift", "DemoData.swift",
                          "DemoFeed.swift", "Reminders.swift", "AgendaBuckets.swift", "WatchDigest.swift"]),
        .testTarget(name: "DayDeckCoreTests", dependencies: ["DayDeckCore"], path: "Tests",
                    exclude: ["check-platform-typecheck.sh"])
    ],
    swiftLanguageVersions: [.v5]
)
