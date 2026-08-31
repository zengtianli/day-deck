import SwiftUI

/// 主用途第一半：**早上打开，看今天要做什么**。
///
/// 分组顺序是刻意的：逾期 → 今天 → 没定时间 → 之后。
/// 「没定时间」不排在最后是有意的 —— 那类占 open 的相当一部分（实测 117 条里一大批），
/// 排到最底下就等于永远看不见，而它们照样是要做的事。
struct TodayView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if let e = store.openError {
                    Section { ErrorBlock(error: e, stale: store.openAt) }
                }
                group("逾期", store.overdue, tint: .red)
                group("今天", store.dueToday, tint: .accentColor)
                group("没定时间", store.undated, tint: .secondary)
                group("之后", store.upcoming, tint: .secondary)

                if store.open.isEmpty && store.openError == nil {
                    // 空集不静默 —— 「一条都没有」和「没取到」看起来一样，必须分开说。
                    Section {
                        Text(store.loading ? "取数中…" : "一条未完成的都没有。")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                }
            }
            .navigationTitle("今天 · \(store.dueToday.count + store.overdue.count)")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Agenda.self) { AgendaDetailView(item: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let at = store.openAt { StaleBadge(at: at) }
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [Agenda], tint: Color) -> some View {
        if !items.isEmpty {
            Section("\(title) · \(items.count)") {
                ForEach(items) { a in
                    NavigationLink(value: a) { AgendaRow(item: a, tint: tint) }
                }
            }
        }
    }
}

struct AgendaRow: View {
    let item: Agenda
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.isEvent ? "calendar" : "circle")
                .font(.callout).foregroundStyle(tint).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.callout)
                HStack(spacing: 6) {
                    if let s = whenText { Text(s).font(.caption2).foregroundStyle(tint) }
                    if let w = item.who, !w.isEmpty {
                        Text(w).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if item.pushed {
                        // 已经进过提醒事项/日历。不标的话会重复推，而重复推**不报错**。
                        Image(systemName: "bell.badge").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(.vertical, 2)
    }

    private var whenText: String? {
        guard let d = item.due else { return nil }
        let f = DateFormatter()
        f.dateFormat = item.allDay ? "M月d日" : "M月d日 HH:mm"
        return f.string(from: d)
    }
}

struct AgendaDetailView: View {
    @Environment(Store.self) private var store
    let item: Agenda
    @State private var busy = false
    @State private var note: String?
    @State private var failed = false

    var body: some View {
        List {
            Section { Text(item.title).font(.headline) }

            Section("动作") {
                // 三个动作都只是**下单**，真正执行在 Mac 上（提醒事项/日历的授权、
                // notif.db、notifhub 二进制全在那边，VPS 和手机都碰不到）。
                // 所以提示语一律说「已排队」，不说「已完成」—— 两者之间隔着 Mac 醒没醒。
                Button { act("done") } label: { Label("标为完成", systemImage: "checkmark.circle") }
                Button { act("dropped") } label: { Label("不做了", systemImage: "xmark.circle") }
                Button { act("push") } label: {
                    Label(item.pushed ? "再推一次提醒事项/日历" : "存进提醒事项/日历",
                          systemImage: "bell.badge")
                }
                if busy { ProgressView() }
                if let n = note {
                    Text(n).font(.caption)
                        .foregroundStyle(failed ? Color.orange : Color.green)
                }
            }
            if let w = item.who, !w.isEmpty { Section("跟谁") { Text(w).font(.callout) } }
            if let d = item.due {
                Section(item.isEvent ? "什么时候" : "什么时候之前") {
                    Text(d.formatted(date: .complete,
                                     time: item.allDay ? .omitted : .shortened)).font(.callout)
                }
            }
            if let n = item.note, !n.isEmpty { Section("备注") { Text(n).font(.callout) } }
            if let e = item.evidence, !e.isEmpty {
                // 佐证是这套东西可信的关键：LLM 抽错了，看一眼原文就知道。
                Section("从哪句话抽出来的") {
                    Text(e).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Section("出处") {
                LabeledContent("来源", value: item.source == "llm" ? "从通知里抽的" : "手动录入")
                if let d = item.srcDate { LabeledContent("哪天", value: d) }
                LabeledContent("已推进提醒事项/日历", value: item.pushed ? "是" : "否")
            }
        }
        .navigationTitle(item.isEvent ? "日程" : "待办")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func act(_ what: String) {
        busy = true; note = nil
        Task {
            let r = what == "push"
                ? await Writer.push(item.id, title: item.title)
                : await Writer.mark(item.id, to: what, title: item.title)
            busy = false
            switch r {
            case .success:
                failed = false
                note = "已排队。Mac 上的 notifhub 每分钟领一次单；落库后下拉刷新就会看到。"
                await store.refresh()
            case .failure(let e):
                failed = true
                note = "\(e.headline) —— \(e.whatToDo)"
            }
        }
    }
}

/// 数据是什么时候的。**离线可读的代价是可能看到旧数据**，所以必须一直显示时间戳 ——
/// 不显示的话，飞行模式下看到的昨天会被当成今天。
struct StaleBadge: View {
    let at: Date
    var body: some View {
        let mins = Int(Date().timeIntervalSince(at) / 60)
        Text(mins < 2 ? "刚刚" : mins < 60 ? "\(mins) 分钟前" : at.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(mins > 180 ? Color.orange : Color.secondary)
    }
}

struct ErrorBlock: View {
    let error: FeedError
    let stale: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error.headline, systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.medium)).foregroundStyle(Color.orange)
            if stale != nil {
                Text("下面显示的是上一次取到的内容。").font(.caption).foregroundStyle(.secondary)
            }
            Text(error.whatToDo).font(.caption)
            Text(error.detail).font(.caption2).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }.padding(.vertical, 2)
    }
}
