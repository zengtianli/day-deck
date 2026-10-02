import Foundation

/// 「今天」页的四个分组：逾期 → 今天 → 没定时间 → 之后。**规则只此一份**：
/// iPhone / iPad / Vision 的「今天」页（经 Store）和手表摘要里的「待办 今天 N · 逾期 M」（WatchDigest）都从这里取，
/// 两处各写一份的话，手表上的数会和手机上的分组悄悄对不上。
///
/// `calendar` 用云端时区（Store.dayCalendar）：划天跟着 notifhub，不跟设备时区走。
enum AgendaBuckets {
    static func overdue(_ open: [Agenda], calendar: Calendar, now: Date = Date()) -> [Agenda] {
        open.filter { ($0.dueTS ?? .infinity) < now.timeIntervalSince1970
            && !calendar.isDate($0.due ?? .distantFuture, inSameDayAs: now) }
    }

    static func dueToday(_ open: [Agenda], calendar: Calendar, now: Date = Date()) -> [Agenda] {
        open.filter { $0.due.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
    }

    static func undated(_ open: [Agenda]) -> [Agenda] {
        open.filter { $0.dueTS == nil }
    }

    static func upcoming(_ open: [Agenda], calendar: Calendar, now: Date = Date()) -> [Agenda] {
        open.filter { item in
            guard let due = item.due else { return false }
            return due > now && !calendar.isDate(due, inSameDayAs: now)
        }
    }
}
