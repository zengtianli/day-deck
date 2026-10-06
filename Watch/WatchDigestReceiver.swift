import Foundation
import WatchConnectivity
import WidgetKit

/// 手表这头接 iPhone 递来的「今天的通知摘要」（发送端见 Sources/WatchLink.swift）。
///
/// 收到 → 比一比是不是比手上这份新（转交顺序不保证，旧的不能盖掉新的）→ 存进 DigestVault →
/// 让表盘复杂功能重画。手表自己不联网：iPhone 没打开过 Notihub 时，这里就停在上一份，界面写明是什么时候的。
/// WCSession 全局只有一个 delegate：只建一个实例（shared）。
@MainActor
final class WatchDigestReceiver: NSObject, ObservableObject {
    static let shared = WatchDigestReceiver()

    @Published private(set) var digest: WatchDigest?
    @Published private(set) var receivedAt: Date?

    override init() {
        super.init()
        #if DEBUG
        // 演示 / 截图：`-demo 1` 只用合成内容（与 iPhone 演示同一份 DemoFeed），不落盘、不碰 WatchConnectivity
        if DemoFeed.enabled {
            let feed = DemoFeed.make()
            digest = WatchDigest.make(day: feed.day, open: feed.open, timezone: feed.timezone,
                                      lastSync: feed.lastSync, now: feed.now)
            receivedAt = feed.now
            Remote.ui = digest?.ui?.value
            return
        }
        #endif
        if let saved = DigestVault.load() {
            Remote.ui = saved.digest.ui?.value   // 读本机那一份：后端改过的话术跟着摘要走
            digest = saved.digest
            receivedAt = saved.receivedAt
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func apply(_ payload: [String: Any]) {
        guard let data = payload[WatchDigest.contextKey] as? Data,
              let incoming = try? JSONDecoder().decode(WatchDigest.self, from: data) else { return }
        if let current = digest, incoming.isOlder(than: current) { return }
        let now = Date()
        Remote.ui = incoming.ui?.value   // 先换覆盖项，再发布摘要触发重画；这份没带就全部回到自带文案
        digest = incoming
        receivedAt = now
        DigestVault.save(.init(digest: incoming, receivedAt: now))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 系统为 WatchConnectivity 在后台唤醒本 App 时：等这次要转交的数据到齐（最多 10 秒）再把后台任务交回。
    func drain() async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState != .activated { session.activate() }
        for _ in 0..<50 where session.activationState != .activated || session.hasContentPending {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

extension WatchDigestReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }

    /// 表盘复杂功能的加急转交（iPhone 只在未读数变了时发）
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.apply(userInfo) }
    }
}
