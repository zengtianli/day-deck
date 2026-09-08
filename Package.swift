// swift-tools-version: 5.9
import PackageDescription

// Tests compile these exact production files; the app remains built by its Xcode project.
let package = Package(
    name: "DayDeckCore",
    platforms: [.macOS("15.0")],
    products: [.library(name: "DayDeckCore", targets: ["DayDeckCore"])],
    targets: [
        .target(name: "DayDeckCore", path: "Sources",
                exclude: ["App.swift", "TodayView.swift", "MarkdownView.swift", "DiaryView.swift", "RecapView.swift"],
                sources: ["API.swift", "Models.swift", "Store.swift", "Gate.swift", "Writer.swift"]),
        .testTarget(name: "DayDeckCoreTests", dependencies: ["DayDeckCore"], path: "Tests")
    ],
    swiftLanguageVersions: [.v5]
)
