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

    // ⚠ **「今天」是哪天，由 notifhub 说了算，不由这台设备说了算。**
    //
    // notifhub 划天走 Mac 的系统时区（`Clock` → `/etc/localtime` = Asia/Shanghai），
    // 站上的文件名就是那把尺子。客户端拿设备时区去拼文件名，人一出国就会去要
    // 一个不存在的日期，表现是「今天这页 404 / 空白」，而错误完全指不出时区。
    //
    // 同一类坑当场撞到过（2026-08-31）：这台 Mac 的 `$TZ=America/Los_Angeles`
    // （给 cc 用的，不是配置错），于是 shell 里 `date +%F` 比 notifhub 认的日期**早一天**，
    // 我照它去 VPS 上查文件，查的是昨天那份、还以为写入没生效。
    static let dayTZ = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func dayString(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = dayTZ
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    static var dayCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = dayTZ
        return c
    }

    /// 兜底用的本地算法。**优先用 `latestDate`（数据派生）** —— 那是 notifhub
    /// 自己发布出来的最新一天，不可能和它自己的划天规则打架。
    static var today: String { dayString() }

    /// 站上最新那天。index 是新→旧排的。
    /// ⚠ **它不等于「今天」** —— 一条明天的日历提醒就能让站上多出一个未来的日期
    /// （实测 2026-08-31 那天站上最新是 09-01，来源是一条明天的天气预报）。
    var latestDate: String { index.first?.date ?? Store.today }

    /// 界面该落在哪一天：**优先今天**（钉死上海，跟 notifhub 划天同一把尺子），
    /// 今天还没发布过才退到站上最新那天。
    /// 直接用 latestDate 的后果：日记页的「今天已记的」会去读明天那一页，永远是 0。
    var landingDate: String {
        let t = Store.today
        if index.isEmpty { return t }
        return index.contains(where: { $0.date == t }) ? t : latestDate
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
        return open.filter { ($0.dueTS ?? .infinity) < now && !Store.dayCalendar.isDateInToday($0.due ?? .distantFuture) }
    }

    /// 今天到期的。
    var dueToday: [Agenda] {
        open.filter { d in d.due.map { Store.dayCalendar.isDateInToday($0) } ?? false }
    }

    /// 没定时间的 —— 不能藏起来，藏起来的表现是待办凭空消失。
    var undated: [Agenda] { open.filter { $0.dueTS == nil } }

    /// 之后的。
    var upcoming: [Agenda] {
        open.filter { d in
            guard let due = d.due else { return false }
            return due > Date() && !Store.dayCalendar.isDateInToday(due)
        }
    }
}
