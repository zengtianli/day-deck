import SwiftUI
import WidgetKit

/// 表盘复杂功能的**视图与时间线条目**，手表 App 与复杂功能扩展共用一份。
///
/// 放这里而不是只留在扩展里：手表 App 的 `-complications 1` 预览页要把它们原样画出来验证 ——
/// 无界面的模拟器上没法把复杂功能挂上表盘，而「装上了」和「画得出来」是两件事。
struct DigestEntry: TimelineEntry {
    let date: Date
    let digest: WatchDigest?
}

struct DigestComplicationView: View {
    // 系统给的尺寸（只读）。预览时用 familyOverride 顶掉 —— environment 改不了它。
    @Environment(\.widgetFamily) private var envFamily
    let entry: DigestEntry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? envFamily }

    /// 只有摘要是「今天」的才显示未读数：过了零点、或 iPhone 好久没打开时，昨天的数不能冒充今天。
    private var today: WatchDigest? {
        guard let d = entry.digest, d.isToday(entry.date) else { return nil }
        return d
    }

    private var countText: String { today.map { "\($0.unread)" } ?? "–" }

    var body: some View {
        // accessory 的底由表盘画，这里给透明底 —— 不声明 containerBackground，系统会用占位顶掉整块。
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bell.fill").font(.system(size: 11, weight: .semibold))
                    Text(countText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
            }
            .widgetAccentable()
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryCorner:
            Image(systemName: "bell.fill")
                .font(.system(size: 20, weight: .semibold))
                .widgetLabel { Text("未读 \(countText)") }
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Label(inlineText, systemImage: "bell")
                .containerBackground(for: .widget) { Color.clear }
        default:   // .accessoryRectangular
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill").font(.caption2)
                    Text("Notihub").font(.headline)
                }
                .widgetAccentable()
                if let d = today {
                    Text("未读 \(d.unread) · 通知 \(d.total) 条").font(.caption)
                    Text(d.headline.isEmpty ? "合并后 \(d.events) 件事" : d.headline)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    // 还没收到过摘要时没有覆盖项可用（话术是跟着摘要来的），那一句只有自带的
                    Text(entry.digest == nil ? "在 iPhone 上打开 Notihub" : T("watch.not_today", "今天的摘要还没同步"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
        }
    }

    private var inlineText: String {
        guard let d = today else { return "Notihub" }
        return "未读 \(d.unread) · \(d.total) 条通知"
    }
}
