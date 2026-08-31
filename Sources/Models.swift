import Foundation

// =============================================================================
// 与 notifhub 的 `Sources/notifhub/JSONFeed.swift` **逐字段对应**。
// 那边是 SSOT，这边是它的读取形状。改字段要两边一起改 ——
// 只改一边的表现是解码失败，而 API.decode 会点名是哪个字段，不会静默容错。
//
// **这里一条业务事实都没有**：合并规则、噪音折叠、时间节点抽取、LLM 总结
// 全在 Mac 上的 notifhub 里。这个 app 只是它的一个视图。
// =============================================================================

struct IndexDay: Codable, Identifiable, Hashable {
    let date: String
    let total: Int          // 合并前的原始通知条数
    let merged: Int         // 合并后的「事」数
    let headline: String    // LLM 一句话；没总结时是空串
    let agendaOpen: Int
    let whos: [String]
    var id: String { date }
}

struct FeedIndex: Codable {
    let generatedAt: Double
    let days: [IndexDay]
}

struct Agenda: Codable, Identifiable, Hashable {
    let id: Int64
    let kind: String        // todo | event
    let title: String
    let note: String?
    let dueTS: Double?
    let endTS: Double?
    let allDay: Bool
    let who: String?
    let evidence: String?   // 从哪条通知抽出来的原文佐证
    let status: String      // open | done | dropped
    let source: String      // llm | manual
    let srcDate: String?
    let pushed: Bool

    var due: Date? { dueTS.map { Date(timeIntervalSince1970: $0) } }
    var isEvent: Bool { kind == "event" }

    /// 「没定时间」的条目也得做，只是排在有时刻的后面。
    /// 用一个远未来的哨兵而不是把它们过滤掉 —— 过滤掉的表现是待办凭空消失。
    var sortKey: Double { dueTS ?? 4_102_444_800 }   // 2100-01-01
}

struct FeedOpen: Codable {
    let generatedAt: Double
    let items: [Agenda]
}

struct FeedItem: Codable, Identifiable, Hashable {
    let ts: Double
    let endTs: Double
    let app: String
    let who: String
    let lines: [String]
    let missed: Bool        // 至今没点开
    let redacted: Bool
    var id: String { "\(ts)-\(app)-\(who)" }

    var start: Date { Date(timeIntervalSince1970: ts) }
    var end: Date { Date(timeIntervalSince1970: endTs) }
}

struct FeedSummary: Codable, Hashable {
    let headline: String
    let text: String
    let generatedAt: Double
}

struct FeedDay: Codable {
    let date: String
    let total: Int
    let muted: Int
    let notes: Int
    let first: Double?
    let last: Double?
    let byHour: [Int]
    let apps: [[String]]    // [[名字, 次数]]
    let whos: [[String]]
    let summary: FeedSummary?
    let agenda: [Agenda]
    let items: [FeedItem]
}
