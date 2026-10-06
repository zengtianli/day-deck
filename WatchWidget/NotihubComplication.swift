import SwiftUI
import WidgetKit

/// 表盘复杂功能：今天还有几件没点开的通知。
///
/// **不联网**：只读手表 App 收到摘要时写进共享钥匙串的那一份（DigestVault）。手表 App 每收到一份就
/// reloadAllTimelines，那才是真正的更新时机；时间线只在云端时区的零点再排一条 —— 过了零点，
/// 昨天的未读数改显示「–」，不冒充今天。
struct DigestProvider: TimelineProvider {
    func placeholder(in context: Context) -> DigestEntry { DigestEntry(date: .now, digest: nil) }

    /// 手表 App 落盘的那份摘要；它带来的话术覆盖项同时交给 T()（复杂功能跑在自己的进程里，要自己接一次）。
    private func latest() -> WatchDigest? {
        let digest = DigestVault.load()?.digest
        Remote.ui = digest?.ui?.value
        return digest
    }

    func getSnapshot(in context: Context, completion: @escaping (DigestEntry) -> Void) {
        completion(DigestEntry(date: .now, digest: latest()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DigestEntry>) -> Void) {
        let digest = latest()
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = digest?.cloudTimeZone ?? .current
        let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [DigestEntry(date: now, digest: digest), DigestEntry(date: midnight, digest: digest)],
                            policy: .never))
    }
}

@main
struct NotihubComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NotihubUnread", provider: DigestProvider()) { entry in
            DigestComplicationView(entry: entry)
        }
        .configurationDisplayName("Notihub")
        .description("今天还有几件通知没点开")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
