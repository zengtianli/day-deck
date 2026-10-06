import Foundation

// =============================================================================
// Apple Watch 上的「今天的通知摘要」：iPhone 从已经取到的那一天（FeedDay）算出来，
// 经 WatchConnectivity 递给手表（Sources/WatchLink.swift → Watch/WatchDigestReceiver.swift），
// 手表 App 与表盘复杂功能只读这一份，**手表自己不联网、不持闸密码**。
//
// 这里没有新的业务事实：总数、合并后件数、未读（至今没点开）都原样取自 notifhub 发布的 FeedDay；
// 待办分组走 AgendaBuckets（与「今天」页同一份规则）。只做裁剪 —— 手表一屏放不下整天的时间线，
// 也不该把整天原文搬到表上：要点最多 6 条、每条只留第一行的前 80 个字。
// =============================================================================

struct WatchDigest: Codable, Equatable {
    struct Count: Codable, Equatable, Hashable {
        let name: String
        let count: Int
    }

    struct Item: Codable, Equatable, Identifiable {
        let ts: Double
        let app: String
        let who: String
        let line: String
        let missed: Bool
        var id: String { "\(ts)-\(app)-\(who)" }
    }

    let date: String          // 摘要的是哪一天（yyyy-MM-dd，云端时区）—— 早上 notifhub 还没发布今天时是最近一天
    let timezone: String      // 云端时区：判「是不是今天」、显示时刻都按它
    let total: Int            // 原始通知条数
    let events: Int           // 合并后的件数
    let muted: Int            // 折叠的噪音
    let unread: Int           // 至今没点开的件数（FeedItem.missed）
    let notes: Int            // 随手记条数
    let headline: String      // LLM 一句话；没总结时是空串
    let apps: [Count]         // 按 App 计数，最多 5 个
    let whos: [Count]         // 聊得最多，最多 3 个
    let top: [Item]           // 未读在前、再按时间倒序，最多 6 条
    let dueToday: Int
    let overdue: Int
    let lastSync: Double?     // 云端最后一次同步（Mac 采集）的时刻
    /// 后端覆盖项（service/ui.json）里手表用得到的那几项，随摘要多传一跳，手表与 iPhone 说同样的话。
    /// 可选：旧摘要没有这一项；`Lenient` 让以后形状变了也只是这一项回落，不连带整份摘要。
    var ui: Lenient<FeedUI>? = nil

    static let contextKey = "digest"
    static let topLimit = 6
    static let lineLimit = 80

    /// 手表显示要用的覆盖项：只有这几个键随摘要走（其余手表用不到；摘要要小，WatchConnectivity 的上下文有大小上限）。
    /// 待办分组名与 iPhone「今天」页是同一组键。
    static let carriedCopy: Set<String> = ["today.group.today", "today.group.overdue", "watch.day_stale",
                                           "watch.sync_at", "watch.sync_never", "watch.no_apps",
                                           "watch.no_items", "watch.not_today"]
    static let carriedLimits: Set<String> = ["stale_seconds"]
    /// 一条话术最多带多少字：再长手表一行也放不下，也不让一条写错的长文把整份摘要撑到发不出去。
    static let carriedCopyLimit = 80

    /// 从 iPhone 手上的覆盖项里摘出手表那几项；一项都没有时返回 nil（摘要与没有覆盖时相同，不多一个键）。
    static func carried(_ ui: FeedUI?) -> Lenient<FeedUI>? {
        guard let ui else { return nil }
        let copy = (ui.copy ?? [:]).filter {
            carriedCopy.contains($0.key) && !$0.value.isEmpty && $0.value.count <= carriedCopyLimit
        }
        let limits = (ui.limits ?? [:]).filter { carriedLimits.contains($0.key) && $0.value.isFinite }
        if copy.isEmpty && limits.isEmpty { return nil }
        return Lenient(FeedUI(copy: copy.isEmpty ? nil : copy, limits: limits.isEmpty ? nil : limits))
    }

    /// 数据多旧算「旧」（标橙）。iPhone 的 StaleBadge 与手表主页用同一个键、同样的自带值与范围。
    static var staleAfter: TimeInterval { Remote.seconds("stale_seconds", 3 * 3600, in: 600...86_400) }

    static func make(day: FeedDay, open: [Agenda], timezone: TimeZone, lastSync: Date?,
                     ui: FeedUI? = nil, now: Date = Date()) -> WatchDigest {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let picked = day.items.sorted { a, b in
            a.missed != b.missed ? a.missed : a.ts > b.ts
        }.prefix(topLimit)
        return WatchDigest(
            date: day.date, timezone: timezone.identifier,
            total: day.total, events: day.items.count, muted: day.muted,
            unread: day.items.filter(\.missed).count,
            notes: day.notes + day.cloudNotes.count,
            headline: day.summary?.headline ?? "",
            apps: counts(day.apps, limit: 5), whos: counts(day.whos, limit: 3),
            top: picked.map { item in
                Item(ts: item.ts, app: item.app, who: item.who, line: firstLine(item), missed: item.missed)
            },
            dueToday: AgendaBuckets.dueToday(open, calendar: calendar, now: now).count,
            overdue: AgendaBuckets.overdue(open, calendar: calendar, now: now).count,
            lastSync: lastSync?.timeIntervalSince1970,
            ui: carried(ui))
    }

    /// FeedDay 里的 `[[名字, 次数]]`；次数不是整数的整行不要（不猜）。
    private static func counts(_ rows: [[String]], limit: Int) -> [Count] {
        Array(rows.compactMap { row in
            guard row.count == 2, let n = Int(row[1]) else { return nil }
            return Count(name: row[0], count: n)
        }.prefix(limit))
    }

    private static func firstLine(_ item: FeedItem) -> String {
        if item.redacted { return T("watch.redacted", "正文已按保留期抹除") }
        let line = item.lines.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        return line.count > lineLimit ? String(line.prefix(lineLimit)) + "…" : line
    }

    var cloudTimeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }

    /// 摘要的那天是不是（云端时区的）今天。过了零点，昨天的未读数不能当今天的显示。
    func isToday(_ now: Date = Date()) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = cloudTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now) == date
    }

    /// 两份摘要谁更新：先比哪一天，再比云端同步时刻。转交顺序不保证，旧的不能盖掉新的。
    func isOlder(than other: WatchDigest) -> Bool {
        (date, lastSync ?? 0) < (other.date, other.lastSync ?? 0)
    }
}
