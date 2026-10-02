import SwiftUI

/// 宽屏与窄屏的**唯一判定入口**，由 RootView 往下传。
///
/// 宽屏 = iPad 全屏 / 宽分屏、Vision Pro：侧栏 + 看板（RegularRootView）。
/// 窄屏 = iPhone（含 Pro Max 横屏，那时尺寸类也会变成 regular）和 iPad 窄分屏：
/// 原来的四个 tab，一个像素都不动 —— 公开演示视频就是这套布局录的。
/// Mac 不在这里：Mac 端是独立的 Notihub Mac（菜单栏 App），本工程不出 Mac 版。
struct WideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }
}

extension View {
    /// 宽屏里的长文本页（复盘、随手记、连接）：背景铺满，内容收在 `maxWidth` 以内居中。
    /// 用 contentMargins 而不是 frame —— frame 会把导航栏和分组底色一起裁窄，看着像一块贴上去的手机屏。
    /// 量出来的宽度只用来算页边距，不反过来改容器尺寸，不会在布局里来回打转。
    func readableWidth(_ maxWidth: CGFloat) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }

    /// 看板上的卡片底：iPad 是分组底色上的一块白卡；Vision Pro 的窗口本身是玻璃，卡片用薄材质浮在上面。
    func boardCard() -> some View {
        #if os(visionOS)
        self.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        #else
        self.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        #endif
    }

    /// 看板整页的底：iPad 与分组列表同一种底色，Vision Pro 保留窗口玻璃。
    @ViewBuilder
    func boardBackground() -> some View {
        #if os(visionOS)
        self
        #else
        self.background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        #endif
    }
}

private struct ReadableWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var frame = Frame()

    struct Frame: Equatable {
        var width: CGFloat = 0
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    /// iPadOS 26 起侧栏浮在详情上面：详情铺到侧栏底下，侧栏宽度算在 leading 安全区里，
    /// 而 contentMargins 与安全区取的是较大的那个 —— 所以页边距要从安全区外沿算起，
    /// 不然左边贴着侧栏、只有右边留白（2026-10-02 iPad 模拟器实测）。最窄也留系统列表的 20pt。
    private var margin: CGFloat { max(20, (frame.width - maxWidth) / 2) }

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, frame.leading + margin, for: .scrollContent)
            .contentMargins(.trailing, frame.trailing + margin, for: .scrollContent)
            .onGeometryChange(for: Frame.self) { proxy in
                Frame(width: proxy.size.width, leading: proxy.safeAreaInsets.leading,
                      trailing: proxy.safeAreaInsets.trailing)
            } action: { frame = $0 }
    }
}
