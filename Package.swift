// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Tests compile these exact production files; the app remains built by its Xcode project.
let core = ["Sources/API.swift", "Sources/Models.swift", "Sources/Store.swift", "Sources/Gate.swift",
            "Sources/Writer.swift", "Sources/DemoData.swift", "Sources/DemoFeed.swift", "Sources/Reminders.swift",
            "Sources/AgendaBuckets.swift", "Sources/WatchDigest.swift",
            // 总部共享文件的逐字节副本：模型（Lenient<FeedUI>）和出错建议（T）都用到它
            "Shared/RemoteUI.swift"]

// 目标根是工程根而不是 Sources/：Shared/ 不在 Sources/ 下，而 SwiftPM 只许点名目标根以内的文件。
// 只编 core 点名的这些；工程根下其余条目（界面源码、手表、构建产物、文档……）按当前目录内容一律排除，
// 不然 SwiftPM 会把整个工程根扫一遍，报几百条「未处理的文件」并把资产目录当资源编进测试包。
func entries(_ directory: String) -> [String] {
    let path = directory.isEmpty ? Context.packageDirectory : Context.packageDirectory + "/" + directory
    return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
        .filter { !$0.hasPrefix(".") && $0 != "Package.swift" && $0 != "Package.resolved" }
        .map { directory.isEmpty ? $0 : directory + "/" + $0 }.sorted()
}
let coreDirectories = Set(core.map { String($0.split(separator: "/")[0]) })
let notCore = entries("").filter { !coreDirectories.contains($0) }
    + coreDirectories.sorted().flatMap(entries).filter { !core.contains($0) }

let package = Package(
    name: "DayDeckCore",
    platforms: [.macOS("15.0")],
    products: [.library(name: "DayDeckCore", targets: ["DayDeckCore"])],
    targets: [
        .target(name: "DayDeckCore", path: ".", exclude: notCore, sources: core),
        .testTarget(name: "DayDeckCoreTests", dependencies: ["DayDeckCore"], path: "Tests",
                    exclude: ["check-platform-typecheck.sh"])
    ],
    swiftLanguageVersions: [.v5]
)
