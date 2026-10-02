import XCTest
import Foundation
@testable import DayDeckCore

/// Apple Watch 摘要：从生产的 FeedDay / Agenda 算出来的数，与 iPhone 各页同一口径；手表只拿裁剪后的一份。
final class WatchDigestTests: XCTestCase {
    private let tz = TimeZone(identifier: "Asia/Shanghai")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    private func item(_ ts: Double, _ who: String, missed: Bool, lines: [String] = ["合成正文"],
                      redacted: Bool = false) -> FeedItem {
        FeedItem(ts: ts, endTs: ts, app: "微信", who: who, lines: lines, missed: missed, redacted: redacted)
    }

    private func agenda(_ id: Int64, due: Double?) -> Agenda {
        Agenda(id: id, kind: "todo", title: "合成待办 \(id)", note: nil, dueTS: due, endTS: nil, allDay: false,
               who: nil, evidence: nil, status: "open", source: "llm", srcDate: nil, pushed: false)
    }

    private func day(_ items: [FeedItem], apps: [[String]] = [["微信", "5"], ["邮件", "x"], ["短信", "2"]]) -> FeedDay {
        FeedDay(date: "2026-10-02", total: 12, muted: 3, notes: 1, first: nil, last: nil, byHour: Array(repeating: 0, count: 24),
                apps: apps, whos: [["甲", "4"], ["乙", "3"], ["丙", "2"], ["丁", "1"]],
                summary: FeedSummary(headline: "合成一句话", text: "**合成**", generatedAt: 0),
                agenda: [], items: items,
                cloudNotes: [CloudNote(id: 1, text: "合成随手记", ts: 0, date: "2026-10-02")])
    }

    func testCountsComeFromTheSameDay() {
        let base = 1_791_000_000.0
        let items = [item(base, "甲", missed: false), item(base + 60, "乙", missed: true), item(base + 120, "丙", missed: true)]
        let digest = WatchDigest.make(day: day(items), open: [], timezone: tz, lastSync: nil)
        XCTAssertEqual(digest.total, 12)
        XCTAssertEqual(digest.events, 3)
        XCTAssertEqual(digest.unread, 2)
        XCTAssertEqual(digest.notes, 2, "本机随手记 + 云端随手记，与复盘页「随手记」同一个数")
        XCTAssertEqual(digest.headline, "合成一句话")
        // 次数不是整数的整行不要（不猜），顺序保留
        XCTAssertEqual(digest.apps, [.init(name: "微信", count: 5), .init(name: "短信", count: 2)])
        XCTAssertEqual(digest.whos.map(\.name), ["甲", "乙", "丙"], "聊得最多最多 3 个")
    }

    func testTopPutsUnreadFirstThenNewestAndTrims() {
        let base = 1_791_000_000.0
        let long = String(repeating: "长", count: 120)
        var items = (0..<8).map { item(base + Double($0) * 60, "人\($0)", missed: false) }
        items.append(item(base - 600, "未读早", missed: true, lines: ["", "  \(long)  "]))
        items.append(item(base - 900, "抹除", missed: true, redacted: true))
        let digest = WatchDigest.make(day: day(items), open: [], timezone: tz, lastSync: nil)
        XCTAssertEqual(digest.top.count, WatchDigest.topLimit)
        XCTAssertEqual(digest.top.map(\.who), ["未读早", "抹除", "人7", "人6", "人5", "人4"])
        XCTAssertEqual(digest.top[0].line, String(repeating: "长", count: WatchDigest.lineLimit) + "…",
                       "第一行非空的那行，裁到 80 字")
        XCTAssertEqual(digest.top[1].line, "正文已按保留期抹除")
    }

    func testAgendaCountsUseTheTodayPageRules() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)   // 云端时区某天中午附近
        let startOfDay = calendar.startOfDay(for: now).timeIntervalSince1970
        let open = [agenda(1, due: startOfDay - 3600),          // 昨天 → 逾期
                    agenda(2, due: startOfDay + 3600),          // 今天已过 → 今天（不算逾期）
                    agenda(3, due: startOfDay + 86_400 + 60),   // 明天 → 之后
                    agenda(4, due: nil)]                        // 没定时间
        let digest = WatchDigest.make(day: day([]), open: open, timezone: tz, lastSync: nil, now: now)
        XCTAssertEqual(digest.overdue, AgendaBuckets.overdue(open, calendar: calendar, now: now).count)
        XCTAssertEqual(digest.dueToday, AgendaBuckets.dueToday(open, calendar: calendar, now: now).count)
        XCTAssertEqual(AgendaBuckets.overdue(open, calendar: calendar, now: now).map(\.id), [1])
        XCTAssertEqual(AgendaBuckets.dueToday(open, calendar: calendar, now: now).map(\.id), [2])
        XCTAssertEqual(AgendaBuckets.upcoming(open, calendar: calendar, now: now).map(\.id), [3])
        XCTAssertEqual(AgendaBuckets.undated(open).map(\.id), [4])
    }

    func testRoundTripTodayAndOrdering() throws {
        let digest = WatchDigest.make(day: day([item(1, "甲", missed: true)]), open: [], timezone: tz,
                                      lastSync: Date(timeIntervalSince1970: 100))
        let decoded = try JSONDecoder().decode(WatchDigest.self, from: JSONEncoder().encode(digest))
        XCTAssertEqual(decoded, digest)
        // 1_790_913_600 = 2026-10-02 12:00（上海）；过了云端时区的零点就不再是「今天」
        XCTAssertTrue(digest.isToday(Date(timeIntervalSince1970: 1_790_913_600)))
        XCTAssertTrue(digest.isToday(Date(timeIntervalSince1970: 1_790_913_600 + 11 * 3600 + 59 * 60)))
        XCTAssertFalse(digest.isToday(Date(timeIntervalSince1970: 1_790_913_600 + 12 * 3600)))
        let newer = WatchDigest.make(day: day([]), open: [], timezone: tz, lastSync: Date(timeIntervalSince1970: 200))
        XCTAssertTrue(digest.isOlder(than: newer))
        XCTAssertFalse(newer.isOlder(than: digest), "转交顺序不保证：旧的不能盖掉新的")
    }

    func testDemoFeedDigestIsSynthetic() {
        let feed = DemoFeed.make()
        let digest = WatchDigest.make(day: feed.day, open: feed.open, timezone: feed.timezone,
                                      lastSync: feed.lastSync, now: feed.now)
        XCTAssertEqual(digest.unread, 2)
        XCTAssertEqual(digest.total, 46)
        XCTAssertTrue(digest.isToday(feed.now))
    }
}
