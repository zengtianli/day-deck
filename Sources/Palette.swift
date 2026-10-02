import SwiftUI

extension Color {
    /// 深底上的主题紫：主题色（AccentColor，theme_sync 从 products.yaml 派生）#6E56CF 是给亮底配的，
    /// 落在 Vision Pro 的玻璃和手表的黑底上，紫色小字几乎看不清（2026-10-02 模拟器截图）。
    /// 同一色相提亮一档，只在这两处深底用；iPhone / iPad 固定亮色，仍用 AccentColor 原色。
    static let accentOnDark = Color(red: 0.72, green: 0.65, blue: 1.0)
}
