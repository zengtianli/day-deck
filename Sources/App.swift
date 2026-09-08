import SwiftUI

@main
struct DayDeckApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store)
                // 亮色固定：早晚各看一次，内容全是长文本；深色底在户外强光下更难读。
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    // 验证通道：`-tab N` 直接落到某个 tab（生产路径上恒为 0）。
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("今天", systemImage: "checklist") }.tag(0)
            RecapView().tabItem { Label("复盘", systemImage: "book.pages") }.tag(1)
            DiaryView().tabItem { Label("日记", systemImage: "square.and.pencil") }.tag(2)
            ConnectionView().tabItem { Label("连接", systemImage: "gearshape") }.tag(3)
        }
        .task {
            await store.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if scenePhase == .active { await store.refresh() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}

private struct ConnectionView: View {
    @Environment(Store.self) private var store
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("云端") {
                    Link("day.tianli.cyou", destination: URL(string: API.shared.base)!)
                    Text("通知、总结、日记和待办在设备间共用同一份云端记录。")
                        .font(.callout).foregroundStyle(.secondary)
                    if let synced = store.lastSync {
                        LabeledContent("最近同步") { Text(synced, style: .relative) }
                    }
                    if let error = store.indexError { ErrorBlock(error: error, stale: store.indexAt) }
                }
                Section {
                    SecureField("访问密码", text: $password).disabled(busy)
                        .textContentType(.password)
                    Button(busy ? "连接中…" : "连接云端") {
                        guard !busy, !password.isEmpty else { return }
                        busy = true; message = nil
                        Task {
                            defer { busy = false }
                            do {
                                try await Gate.login(password: password, session: API.shared.session)
                                guard Gate.savePassword(password) else {
                                    throw Gate.Failure(message: "连接成功，但钥匙串未能保存凭据，请重试。")
                                }
                                password = ""
                                await store.refresh()
                                failed = store.indexError != nil
                                message = failed ? "登录成功，读取记录时遇到问题，请稍后刷新。" : "云端已连接"
                            } catch {
                                failed = true
                                message = (error as? Gate.Failure)?.message ?? error.localizedDescription
                            }
                        }
                    }.disabled(busy || password.isEmpty)
                    if let message {
                        Label(message, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                            .foregroundStyle(failed ? Color.orange : .green).font(.callout)
                    }
                } header: {
                    Text("登录或更新凭据")
                } footer: {
                    Text("验证成功后，访问密码只保存在系统钥匙串。")
                }
            }.navigationTitle("连接")
        }
    }
}
