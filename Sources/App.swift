import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct NotihubApp: App {
    @State private var store = Store()
    // 系统提醒事项：只在内存里；启动时不请求授权，第一次点「加入」或「允许访问」才弹。
    @State private var reminders = RemindersModel(store: makeReminderStore())

    init() {
        #if DEBUG
        // 验证通道：`-reminderSelfTest <文件名>` 跑模拟器 EventKit 自检（Release 不含此分支）。
        ReminderSelfTest.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(reminders)
                .appLifecycleMobile(productID: "day-deck", channel: MobileProductLifecycle.channel, configuration: MobileProductLifecycle.configuration, placement: .settings)
                #if os(visionOS)
                // Vision Pro 不固定亮色：窗口是系统玻璃，强行亮色会把正文画成玻璃上的深色字。
                // 主题紫在玻璃上太暗，整窗换成提亮一档的同色相（Color.accentOnDark）。
                .accentColor(.accentOnDark)
                .tint(.accentOnDark)
                #else
                // 亮色固定：早晚各看一次，内容全是长文本；深色底在户外强光下更难读。
                .preferredColorScheme(.light)
                #endif
        }
        #if os(visionOS)
        // Vision Pro 的默认窗口偏小：给一个侧栏 + 看板正好铺开的尺寸。
        .defaultSize(width: 1280, height: 820)
        #endif
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    // 验证通道：`-tab N` 直接落到某个 tab（生产路径上恒为 0）。
    // 宽窄两套布局共用这一个选中值：iPad 分屏宽窄来回切时停在同一页。
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")
    #if os(visionOS)
    private let wide = true      // Vision Pro 的窗口一律按宽屏排
    #else
    @Environment(\.horizontalSizeClass) private var hSize
    /// 只认 iPad 的 regular：iPhone Pro Max 横屏时尺寸类也是 regular，但那块屏摆不下侧栏 + 看板，
    /// 仍走原来的四个 tab。
    private var wide: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    #endif

    /// 有东西可显示了（缓存或刚取到的）：平台验收车道的「第一屏有数据」信号就打在这一刻。
    private var hasData: Bool { store.openAt != nil || store.indexAt != nil }

    var body: some View {
        Group {
            if wide {
                RegularRootView(tab: $tab)
            } else {
                TabView(selection: $tab) {
                    TodayView()
                        .tabItem { Label("今天", systemImage: "checklist") }.tag(0)
                    RecapView().tabItem { Label("通知", systemImage: "bell") }.tag(1)
                    DiaryView().tabItem { Label("随手记", systemImage: "square.and.pencil") }.tag(2)
                    ConnectionView().tabItem { Label("连接", systemImage: "gearshape") }.tag(3)
                }
            }
        }
        .environment(\.wideLayout, wide)
        .onAppear { if hasData { LaneSignal.ready(wide ? "board" : "tabs") } }
        .onChange(of: hasData) { _, ready in if ready { LaneSignal.ready(wide ? "board" : "tabs") } }
        .task {
            LaneSignal.applyOrientation()
            LaneSignal.applyWindowFrame()
            // 只有 iPhone 配了手表、手表上装着本 App 时才真的做事（见 WatchLink）
            WatchLink.shared.activate(store: store)
            await store.refresh()
            await WatchLink.shared.sync()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if scenePhase == .active {
                    await store.refresh()
                    await WatchLink.shared.sync()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await store.refresh()
                    await WatchLink.shared.sync()
                }
            }
        }
    }
}

struct ConnectionView: View {
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
                    Text("通知、总结、随手记和待办与 Notihub Mac 共用同一份云端记录。")
                        .font(.callout).foregroundStyle(.secondary)
                    if let synced = store.lastSync {
                        LabeledContent("最近同步") { Text(synced, style: .relative) }
                    }
                    if let error = store.indexError { ErrorBlock(error: error, stale: store.indexAt) }
                }
                ReminderConnectionSection()
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
                Section("应用") {
                    AppLifecycleMobileEntry()
                }
            }.navigationTitle("连接")
        }
    }
}
