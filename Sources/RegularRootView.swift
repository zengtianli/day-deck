import Charts
import SwiftUI

/// 宽屏（iPad 全屏 / 宽分屏、Vision Pro）：侧栏四项 + 详情。
///
/// 为什么不把窄屏的四个 tab 直接拉宽：iPad 上一行待办撑满约 1000pt，标题和时间隔着半个屏，
/// 而右边大片空白本来可以放「这一天发生了什么」。宽屏的「今天」改成看板：左边待办，右边当天的总结、
/// 数、时段和来源 —— 早上一眼同时看到要做的和发生的。复盘、随手记、连接是长文本页，
/// 用同一份视图、收在可读宽度里。行、详情、错误块都是窄屏同一份（TodayView / RecapView / DiaryView），这里只管摆法。
struct RegularRootView: View {
    @Environment(Store.self) private var store
    @Binding var tab: Int

    enum Pane: Int, CaseIterable, Identifiable {
        case today, recap, diary, connection
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .today: return "今天"
            case .recap: return "通知"
            case .diary: return "随手记"
            case .connection: return "连接"
            }
        }
        // 与窄屏 tab 同一套图标
        var icon: String {
            switch self {
            case .today: return "checklist"
            case .recap: return "bell"
            case .diary: return "square.and.pencil"
            case .connection: return "gearshape"
            }
        }
    }

    private var pane: Pane { Pane(rawValue: tab) ?? .today }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch pane {
            case .today: TodayBoard(openRecap: { tab = Pane.recap.rawValue })
            case .recap: RecapView().readableWidth(760)
            case .diary: DiaryView().readableWidth(720)
            case .connection: ConnectionView().readableWidth(640)
            }
        }
    }

    private var sidebar: some View {
        List(selection: Binding<Int?>(get: { tab }, set: { if let v = $0 { tab = v } })) {
            Section {
                ForEach(Pane.allCases) { p in
                    Label(p.title, systemImage: p.icon)
                        .badge(badge(p))
                        .tag(p.rawValue as Int?)
                }
            }
            Section("云端") { SyncStatusRow() }
        }
        .navigationTitle("Notihub")
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
    }

    /// 今天 = 逾期 + 今天到期（与窄屏「今天 · N」同一个数）；通知 = 最近一天至今没点开的件数。
    private func badge(_ p: Pane) -> Int {
        switch p {
        case .today: return store.overdue.count + store.dueToday.count
        case .recap: return store.days[store.landingDate]?.items.filter(\.missed).count ?? 0
        default: return 0
        }
    }
}

/// 侧栏底部：数据是什么时候的、连不连得上。离线可读的代价是可能看到旧数据，所以一直露着（同 StaleBadge）。
private struct SyncStatusRow: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(store.indexError == nil ? Color.green : Color.orange).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.indexError == nil ? "day.tianli.cyou" : store.indexError!.headline)
                    .font(.caption.weight(.medium))
                if let sync = store.lastSync {
                    HStack(spacing: 3) {
                        Text("最后同步").font(.caption2).foregroundStyle(.secondary)
                        StaleBadge(at: sync)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 今天看板

/// 宽屏的「今天」：够宽（≥ 700pt，iPad 竖屏开着侧栏也够）时左栏待办、右栏这一天；更窄的窗口只留待办。
struct TodayBoard: View {
    @Environment(Store.self) private var store
    let openRecap: () -> Void
    // 验证通道：`-search 关键词` 启动即带入搜索（同窄屏）。
    @State private var search = UserDefaults.standard.string(forKey: "search") ?? ""

    private var date: String { store.landingDate }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                // 只拿宽度选一栏还是两栏、分多宽，不拿它反过来定容器尺寸
                if geo.size.width >= 700 {
                    let listWidth = min(500, max(340, geo.size.width * 0.42))
                    HStack(spacing: 0) {
                        TodayList(search: search)
                            .frame(width: listWidth)
                        Divider().ignoresSafeArea(edges: .bottom)
                        DayColumn(date: date, narrow: geo.size.width - listWidth < 600, openRecap: openRecap)
                    }
                } else {
                    TodayList(search: search)
                }
            }
            .boardBackground()
            .navigationTitle("今天 · \(store.dueToday.count + store.overdue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索待办")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Agenda.self) { AgendaDetailView(item: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let at = store.openAt { StaleBadge(at: at) }
                }
                ToolbarItem(placement: .primaryAction) {
                    // 外接键盘时 ⌘R；Vision Pro 上没有下拉刷新的手势，也要一个看得见的按钮
                    // 当天那份跟着 indexAt 变化重取（下面的 onChange），这里只刷三份总表
                    Button { Task { await store.refresh() } } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .task(id: date) { await store.day(date) }
            .onChange(of: store.indexAt) { _, _ in Task { await store.day(date, force: true) } }
        }
    }
}

/// 看板右栏：这一天发生了什么。数据全取自同一份 FeedDay（与「通知」页一致），只换摆法。
private struct DayColumn: View {
    @Environment(Store.self) private var store
    let date: String
    /// 右栏不到 600pt（iPad 竖屏）：数字两两一行、时段与来源上下摆
    let narrow: Bool
    let openRecap: () -> Void

    private var day: FeedDay? { store.days[date] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let e = store.dayError[date] {
                    ErrorBlock(error: e, stale: store.dayAt[date]).boardCard()
                }
                if let d = day {
                    summary(d)
                    stats(d)
                    if narrow {
                        hours(d)
                        sources(d)
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            hours(d)
                            sources(d)
                        }
                    }
                    Button(action: openRecap) {
                        Label("看这天的完整时间线", systemImage: "list.bullet.rectangle")
                    }
                    .padding(.top, 2)
                } else if store.dayError[date] == nil {
                    Text("取数中…").font(.callout).foregroundStyle(.secondary).boardCard()
                }
            }
            .padding(20)
        }
    }

    private var dateLabel: String {
        guard date != store.displayToday else { return "今天" }
        return date   // 早上 notifhub 还没发布今天时，落在最近一天 —— 说清楚是哪天
    }

    private func summary(_ d: FeedDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这一天 · \(dateLabel)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let s = d.summary {
                Text(s.headline).font(.title3.weight(.semibold))
                // LLM 的「几条线」必须真渲染（全局产物规范：露出字面 ** 即不合格）
                MarkdownText(text: s.text)
            } else {
                Text("这天还没有生成总结，完整时间线里仍可查看通知与随手记。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .boardCard()
    }

    private func stats(_ d: FeedDay) -> some View {
        let unread = d.items.filter(\.missed).count
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: narrow ? 2 : 4),
                         spacing: 12) {
            tile("通知", "\(d.total)", "条")
            tile("合并后", "\(d.items.count)", "件事")
            tile("未读", "\(unread)", "件", tint: unread > 0 ? .orange : nil)
            tile("随手记", "\(d.notes + d.cloudNotes.count)", "条")
        }
    }

    private func tile(_ title: String, _ value: String, _ unit: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint ?? .primary)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .boardCard()
    }

    /// 什么时候来的：按小时的条数（FeedDay.byHour，云端时区）。
    private func hours(_ d: FeedDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("什么时候来的").font(.subheadline.weight(.semibold))
            // 小时当类别轴（"0"…"23"）：数值轴上的柱子按比例取宽会被算成 0 宽，整张图只剩网格（2026-10-02 iPad 实测）
            Chart {
                ForEach(Array(d.byHour.enumerated()), id: \.offset) { hour, count in
                    BarMark(x: .value("时", String(hour)), y: .value("条", count), width: .ratio(0.7))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(2)
                }
            }
            .chartXAxis {
                // 类别轴上 values: 不筛刻度（Vision Pro 上 24 个标签挤成一排，2026-10-02 实测），在这里自己只留四个
                AxisMarks { value in
                    if let h = value.as(String.self), ["0", "6", "12", "18"].contains(h) {
                        AxisValueLabel { Text("\(h)时") }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 150)
        }
        .boardCard()
    }

    /// 来自哪里：按 App 的条数 + 聊得最多的人 / 群（FeedDay.apps / whos）。
    private func sources(_ d: FeedDay) -> some View {
        let apps = d.apps.compactMap { row -> (String, Int)? in
            row.count == 2 ? Int(row[1]).map { (row[0], $0) } : nil
        }.prefix(5)
        let top = max(1, apps.map(\.1).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("来自哪里").font(.subheadline.weight(.semibold))
            ForEach(Array(apps), id: \.0) { name, count in
                HStack(spacing: 8) {
                    Text(name).font(.callout).frame(width: 56, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        Capsule().fill(Color.accentColor.opacity(0.75))
                            .frame(width: max(6, g.size.width * CGFloat(count) / CGFloat(top)))
                    }
                    .frame(height: 8)
                    Text("\(count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                }
            }
            if let whos = whosLine(d) {
                Divider()
                Label(whos, systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
            }
        }
        .boardCard()
    }

    private func whosLine(_ d: FeedDay) -> String? {
        let parts = d.whos.prefix(3).compactMap { $0.count == 2 ? "\($0[0]) \($0[1])" : nil }
        return parts.isEmpty ? nil : "聊得最多：" + parts.joined(separator: " · ")
    }
}
