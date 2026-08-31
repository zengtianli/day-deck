import Foundation

/// 全 app 的状态。三份数据各自独立刷新 —— 一份取失败不该让另两份也空着。
@Observable @MainActor
final class Store {
    // 今天要做什么（跨天，不只是今天那一页里的）
    var open: [Agenda] = []
    var openError: FeedError?
    var openAt: Date?

    // 有哪些天
    var index: [IndexDay] = []
    var indexError: FeedError?
    var indexAt: Date?

    // 某一天的详情，按日期缓存在内存里（翻回去不重取）
    var days: [String: FeedDay] = [:]
    var dayError: [String: FeedError] = [:]

    var loading = false

    /// 今天的日期字符串，跟 notifhub 一样走系统时区（那边 `Clock.sqlDay` 用 localtime）。
    /// 用 UTC 的话每天 08:00 之前会翻到前一天，而界面上完全看不出为什么。
    static var today: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        async let o = API.shared.get("/open.json", as: FeedOpen.self)
        async let i = API.shared.get("/index.json", as: FeedIndex.self)
        let (ov, oe, oat) = await o
        let (iv, ie, iat) = await i
        if let v = ov { open = v.items.sorted { $0.sortKey < $1.sortKey } }
        openError = oe; openAt = oat
        if let v = iv { index = v.days }
        indexError = ie; indexAt = iat
    }

    @discardableResult
    func day(_ date: String, force: Bool = false) async -> FeedDay? {
        if !force, let d = days[date] { return d }
        let (v, e, _) = await API.shared.get("/\(date).json", as: FeedDay.self)
        if let v { days[date] = v }
        dayError[date] = e
        return v
    }

    // MARK: - 派生

    /// 逾期的（有到期时刻且已过），最该先看。
    var overdue: [Agenda] {
        let now = Date().timeIntervalSince1970
        return open.filter { ($0.dueTS ?? .infinity) < now && !Calendar.current.isDateInToday($0.due ?? .distantFuture) }
    }

    /// 今天到期的。
    var dueToday: [Agenda] {
        open.filter { d in d.due.map { Calendar.current.isDateInToday($0) } ?? false }
    }

    /// 没定时间的 —— 不能藏起来，藏起来的表现是待办凭空消失。
    var undated: [Agenda] { open.filter { $0.dueTS == nil } }

    /// 之后的。
    var upcoming: [Agenda] {
        open.filter { d in
            guard let due = d.due else { return false }
            return due > Date() && !Calendar.current.isDateInToday(due)
        }
    }
}
