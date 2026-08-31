import SwiftUI

/// 写这一半。**写的东西不落在手机里，落进 Mac 上的 `notif.db`** ——
/// 只存本地的话，日记和复盘会分家：复盘在 day 站上，日记在手机上，
/// 而复盘的价值恰恰是「这一天的事 + 我当时怎么想」摞在一起看。
///
/// 通路复用站上那个「⏰ 存进提醒事项」按钮的下单口（`web_to_local_job_queue` 模式）：
/// 手机只 POST 一张单 → VPS 队列文件 → Mac 上 notifhub 每分钟领单 → `notifhub note`。
/// **这里不写库、不判重、不解析时间**，那些全在 Mac 侧的现成实现里。
struct DiaryView: View {
    @Environment(Store.self) private var store
    @State private var text = ""
    @State private var sending = false
    @State private var result: String?
    @State private var failed = false
    @FocusState private var focused: Bool

    private var day: FeedDay? { store.days[store.landingDate] }

    var body: some View {
        NavigationStack {
            Form {
                Section("今天写点什么") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .focused($focused)
                        .font(.callout)
                    HStack {
                        Text("\(text.count) 字").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            Task { await send() }
                        } label: {
                            if sending { ProgressView() } else { Text("记下来") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let r = result {
                    Section {
                        Label(r, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(failed ? Color.orange : Color.green)
                        if !failed {
                            // 说清楚它还没落库 —— 「已提交」和「已记下」是两件事，
                            // 中间隔着 Mac 醒没醒。混为一谈的表现是：以为写了，回头库里没有。
                            Text("已排队。Mac 上的 notifhub 每分钟领一次单，落库后会出现在下面「今天已记的」里。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if let d = day, d.notes > 0 {
                        // 随手记在时间线里是一个伪 app（notifhub 的 `Recap.noteApp`），
                        // 所以从当天的 items 里按它筛出来，不另开一个端点。
                        ForEach(d.items.filter { $0.app == "随手记" }) { it in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.start.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                                ForEach(Array(it.lines.enumerated()), id: \.offset) { _, l in
                                    Text(l).font(.callout)
                                }
                            }.padding(.vertical, 2)
                        }
                    } else if let e = store.dayError[store.landingDate], day == nil {
                        // **失败不能长得像加载中**。2026-08-31 实测踩到：站上那天的 JSON
                        // 被删掉了（另一处 bug），这里一直显示「取数中…」，看不出是 404。
                        ErrorBlock(error: e, stale: nil)
                    } else {
                        // 不说「今天还没记」—— 那是断言。站上这份是 Mac 上一次 publish
                        // 生成的，刚提交的那条还没进去；说成「没记」会让人以为写丢了。
                        Text(day == nil ? "取数中…" : "站上这一份里还没有今天的随手记。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("今天已记的 · \(day?.notes ?? 0)")
                } footer: {
                    Text("这一节读的是 day 站上那份日报，Mac 每次 `notifhub publish` 才更新。刚提交的条目会在下一次发布后出现。")
                        .font(.caption2)
                }

                Section("这是怎么落进去的") {
                    // ⚠ 必须是**单个字面量** —— `Text("a" + "b")` 的实参类型是 String，
                    // 走 Text(_: StringProtocol) 那个重载，markdown 不渲染，
                    // `**` 会带着星号原样印在屏幕上（2026-08-31 截图实见，
                    // 与 options-desk CLAUDE.md 记的坑 ⑥ 同一条）。
                    Text("手机只提交一张单到 day 站（同一道密码闸），Mac 上的 notifhub 领单后跑 `notifhub note`，写进本机的 notif.db。**通知库本身不出本机。**")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("日记")
            .navigationBarTitleDisplayMode(.inline)
            // id 必须是 latestDate:index 还没到手时它退化成本地算的今天,
            // 拿 `.task {}`(只在出现时跑一次)会永远停在「取数中…」——
            // 截图实见(2026-08-31),而界面上完全看不出是在等 index。
            .task(id: store.landingDate) { await store.day(store.landingDate) }
            .refreshable { await store.day(store.landingDate, force: true) }
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("收起键盘") { focused = false }
                }
            }
        }
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        defer { sending = false }
        switch await Writer.note(body) {
        case .success:
            failed = false
            result = "已提交"
            text = ""
            focused = false
            // 立刻拉一次当天 —— 多半还没落库（领单要一分钟），但下拉刷新就能看到它出现。
            await store.day(store.landingDate, force: true)
        case .failure(let e):
            failed = true
            // 失败时**不清空输入框**：清了就等于把用户刚写的东西弄丢了。
            result = "\(e.headline) —— \(e.whatToDo)"
        }
    }
}

/// 写入面。三种单和 `notifhub` 的接单器一一对应，形状定义在
/// `~/Dev/stations/website/app/api/admin/agenda-queue/route.ts`。
enum Writer {
    static let endpoint = URL(string: "https://day.tianli.cyou/api/agenda-queue")!

    static func note(_ text: String) async -> Result<Void, FeedError> {
        await post(["kind": "note", "text": text])
    }

    static func mark(_ id: Int64, to: String, title: String) async -> Result<Void, FeedError> {
        await post(["kind": "status", "agendaId": id, "to": to, "title": title])
    }

    static func push(_ id: Int64, title: String) async -> Result<Void, FeedError> {
        // force 一律带上：不带的话 notifhub 那侧走「已推过，跳过」分支并且 rc=0，
        // 队列回写 done、界面显示成功，而提醒事项里一条没多。
        await post(["kind": "push", "agendaId": id, "title": title, "force": true])
    }

    private static func post(_ body: [String: Any]) async -> Result<Void, FeedError> {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let shown = endpoint.absoluteString
        do {
            var (data, resp) = try await API.shared.session.data(for: req)
            if Gate.blocked(resp) {
                guard let pw = Gate.password else {
                    return .failure(.gate(url: shown, reason: "这台设备还没有闸凭证"))
                }
                do { try await Gate.login(password: pw, session: API.shared.session) }
                catch { return .failure(.gate(url: shown,
                    reason: (error as? Gate.Failure)?.message ?? "登录失败")) }
                (data, resp) = try await API.shared.session.data(for: req)
            }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                return .failure(.http(url: shown, status: code,
                                      body: String(data: data, encoding: .utf8) ?? "<非文本>"))
            }
            // 服务端回 `{item:{...}}`。回不出 item 就是契约变了 —— 不当成功。
            guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  o["item"] != nil else {
                return .failure(.decoding(url: shown, field: "item",
                                          detail: "下单接口没有回 item，不能当成已排队"))
            }
            return .success(())
        } catch {
            return .failure(.network(url: shown, underlying: (error as NSError).localizedDescription))
        }
    }
}
