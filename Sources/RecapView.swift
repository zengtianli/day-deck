import SwiftUI

/// 主用途另一半：**晚上打开，看今天发生了什么**。
///
/// 默认落在今天。往回翻是主动作（复盘的价值一半在「上周那件事后来怎么样了」），
/// 所以日期切换放在顶部工具栏，不是埋在设置里。
struct RecapView: View {
    @Environment(Store.self) private var store
    // 初值留空，等 index 到手后落到**站上最新那天**（数据派生，不自己算今天）。
    // 自己算的话，设备时区和 notifhub 的划天规则一旦不一致就会去要一个不存在的日期。
    @State private var date = ""
    @State private var showPicker = false

    private var day: FeedDay? { store.days[date] }

    var body: some View {
        NavigationStack {
            List {
                if let e = store.dayError[date], day == nil {
                    Section { ErrorBlock(error: e, stale: nil) }
                }

                if let d = day {
                    if let s = d.summary {
                        Section("这一天") {
                            Text(s.headline).font(.headline)
                            // 「几条线」是 LLM 输出的 markdown，必须真渲染 ——
                            // 露出字面 `**` 或行首 `##` 即不合格（全局产物规范）。
                            MarkdownText(text: s.text)
                        }
                    } else {
                        Section {
                            // 没总结不是「没内容」，得说清楚是哪种情况
                            Text("这天还没总结。Mac 上跑 `notifhub summarize \(date)`。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }

                    Section("这天抽出来的事 · \(d.agenda.count)") {
                        if d.agenda.isEmpty {
                            Text("没抽出时间节点").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(d.agenda) { a in
                                NavigationLink(value: a) {
                                    AgendaRow(item: a, tint: a.status == "open" ? .accentColor : .secondary)
                                }
                            }
                        }
                    }

                    Section("这天的数") {
                        LabeledContent("通知", value: "\(d.total) 条")
                        LabeledContent("合并后", value: "\(d.items.count) 件事")
                        if d.muted > 0 { LabeledContent("折叠的噪音", value: "\(d.muted) 条") }
                        if d.notes > 0 { LabeledContent("随手记", value: "\(d.notes) 条") }
                        if let who = d.whos.first, who.count == 2 {
                            LabeledContent("聊得最多", value: "\(who[0])（\(who[1]) 条）")
                        }
                    }

                    Section("时间线 · \(d.items.count)") {
                        ForEach(d.items) { TimelineRow(item: $0) }
                    }
                } else if store.dayError[date] == nil {
                    Section { Text("取数中…").font(.callout).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(date.isEmpty ? "复盘" : date)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Agenda.self) { AgendaDetailView(item: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(prevDate == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(nextDate == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPicker = true } label: { Image(systemName: "calendar") }
                }
            }
            .sheet(isPresented: $showPicker) { DayPicker(date: $date) }
            .task(id: date) { if !date.isEmpty { await store.day(date) } }
            .task(id: store.index.count) { if date.isEmpty { date = store.landingDate } }
            .refreshable { if !date.isEmpty { await store.day(date, force: true) } }
        }
    }

    /// 只在**有数据的日期之间**走。按自然日 ±1 会走进一堆 404 空页 ——
    /// 那不是「那天没事」，是那天根本没发布，两者在界面上必须分得开。
    private var dates: [String] { store.index.map(\.date) }
    private var prevDate: String? {
        guard let i = dates.firstIndex(of: date) else { return dates.first }
        return i + 1 < dates.count ? dates[i + 1] : nil   // index 是新→旧
    }
    private var nextDate: String? {
        guard let i = dates.firstIndex(of: date), i > 0 else { return nil }
        return dates[i - 1]
    }
    private func step(_ n: Int) {
        if let d = n < 0 ? prevDate : nextDate { date = d }
    }
}

struct DayPicker: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var date: String

    var body: some View {
        NavigationStack {
            List(store.index) { d in
                Button {
                    date = d.date; dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(d.date).font(.callout.weight(.medium))
                            if d.agendaOpen > 0 {
                                Text("\(d.agendaOpen) 个时间节点").font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer()
                            Text("\(d.total) 条").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(d.headline.isEmpty ? d.whos.joined(separator: " · ") : d.headline)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.padding(.vertical, 2)
                }.buttonStyle(.plain)
            }
            .navigationTitle("挑一天 · \(store.index.count)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TimelineRow: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(timeText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(item.app).font(.caption2)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.secondary)
                Text(item.who).font(.caption.weight(.medium)).lineLimit(1)
                if item.missed {
                    Text("未读").font(.caption2).foregroundStyle(Color.orange)
                }
            }
            ForEach(Array(item.lines.enumerated()), id: \.offset) { _, l in
                Text(l).font(.callout).textSelection(.enabled)
            }
            if item.redacted {
                // 正文过了保留窗口被抹掉 —— 说出来，别显示成「这条本来就没内容」
                Text("正文已按保留期抹除").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }

    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let a = f.string(from: item.start)
        let b = f.string(from: item.end)
        return a == b ? a : "\(a)–\(b)"
    }
}
