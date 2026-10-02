import SwiftUI
import WidgetKit

/// Apple Watch 版：抬腕看一眼**今天的通知**—— 还有几件没点开、来了多少、从哪来、要点是什么。
///
/// 和 iPhone 是同一份数据：iPhone 从已经取到的那天算出摘要递过来（WatchLink → WatchDigestReceiver），
/// 手表不联网、不持闸密码、不开长连接；抬腕只读手上这一份，写明是什么时候同步的。
/// 不在表上做「标完成 / 写随手记」：那些是 iPhone 上要看原文、要输字的事。
@main
struct NotihubWatchApp: App {
    @StateObject private var link = WatchDigestReceiver.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(link)
                // 黑底上主题紫的小字太暗：提亮一档（Sources/Palette.swift）
                .accentColor(.accentOnDark)
                .tint(.accentOnDark)
        }
        // iPhone 在后台递来新摘要时，系统为 WatchConnectivity 唤醒本 App：收完再交回
        .backgroundTask(.watchConnectivity) {
            await WatchDigestReceiver.shared.drain()
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var link: WatchDigestReceiver

    var body: some View {
        Group {
            #if DEBUG
            // 验证通道：`-complications 1` 把四种表盘复杂功能原样画出来（无界面模拟器挂不上表盘）
            if UserDefaults.standard.bool(forKey: "complications") {
                ComplicationGallery(digest: link.digest)
            } else {
                content
            }
            #else
            content
            #endif
        }
        .task {
            LaneSignal.applyOrientation()
            LaneSignal.applyWindowFrame()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let digest = link.digest {
            WatchHomeView(digest: digest, receivedAt: link.receivedAt)
        } else {
            WatchWaitingView()
        }
    }
}

/// 还没收到过摘要：只说一句话，指向 iPhone。表上不放登录框。
struct WatchWaitingView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text("在 iPhone 上打开 Notihub")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("今天的通知摘要会自动同步到手表")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
    }
}

#if DEBUG
/// 表盘复杂功能的四种尺寸，按真实表盘上的大小摆出来（只给验证截图用，Release 不含）。
private struct ComplicationGallery: View {
    let digest: WatchDigest?

    var body: some View {
        let entry = DigestEntry(date: .now, digest: digest)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DigestComplicationView(entry: entry, familyOverride: .accessoryCircular)
                        .frame(width: 50, height: 50)
                    DigestComplicationView(entry: entry, familyOverride: .accessoryCorner)
                        .frame(width: 50, height: 50)
                }
                DigestComplicationView(entry: entry, familyOverride: .accessoryRectangular)
                    .frame(height: 52)
                DigestComplicationView(entry: entry, familyOverride: .accessoryInline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .onAppear { LaneSignal.ready("watch-complications") }
    }
}
#endif
