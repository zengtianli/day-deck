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
    // 验证通道：`-tab N` 直接落到某个 tab（生产路径上恒为 0）。
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("今天", systemImage: "checklist") }.tag(0)
            RecapView().tabItem { Label("复盘", systemImage: "book.pages") }.tag(1)
            DiaryView().tabItem { Label("日记", systemImage: "square.and.pencil") }.tag(2)
        }
        .task { await store.refresh() }
    }
}
