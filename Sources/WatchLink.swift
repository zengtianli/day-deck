import Foundation
#if os(iOS)
import WatchConnectivity
#endif

/// iPhone → Apple Watch：把「今天的通知摘要」（WatchDigest）递给手表。
///
/// 手表不联网、不持闸密码 —— 闸的会话 cookie 是整个 `.tianli.cyou` 站群的钥匙，不往表上搬；
/// 手表要的只是一天的几个数和几条要点，由 iPhone 从已经取到的那天算好递过去。
/// 走 `updateApplicationContext`：只保留最新一份，手表下次打开（或被系统唤醒）就能读到，iPhone 不用开着；
/// 表盘上挂了复杂功能、且未读数变了时，再加一份 `transferCurrentComplicationUserInfo`（有每日次数预算，只在数变时用）。
///
/// 没配对手表、手表上没装本 App 时什么都不做，连当天的数都不为它多取 —— 这是常态，不是故障。
/// iPad、Vision Pro 上这里全是空操作（WatchConnectivity 只在 iPhone 上可用）。
/// 手表那头的接收在 Watch/WatchDigestReceiver.swift。
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    #if os(iOS)
    private weak var store: Store?
    /// 上一份发出去的摘要：内容没变就不再发（iPhone 每 60 秒刷新一次，不能每次都往表上推）。
    private var sent: WatchDigest?
    private var sentUnread: Int?

    func activate(store: Store) {
        self.store = store
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated { session.activate() }
    }

    /// 手表上装着本 App 才值得为它取当天的数。
    private var watchReady: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    /// 取（或复用 60 秒内的缓存）最近一天，算摘要，内容变了才发。
    func sync() async {
        guard watchReady, let store else { return }
        #if DEBUG
        // 演示数据不往真手表上推。
        if DemoData.enabled { return }
        #endif
        let date = store.landingDate
        guard let day = await store.day(date) else { return }
        publish(WatchDigest.make(day: day, open: store.open, timezone: store.cloudTimezone, lastSync: store.lastSync))
    }

    private func publish(_ digest: WatchDigest) {
        guard digest != sent, let data = try? JSONEncoder().encode(digest) else { return }
        let session = WCSession.default
        let payload: [String: Any] = [WatchDigest.contextKey: data]
        do { try session.updateApplicationContext(payload) } catch { return }
        sent = digest
        if session.isComplicationEnabled, digest.unread != sentUnread, session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(payload)
        }
        sentUnread = digest.unread
    }

    /// 换表、装上手表 App、表盘加上复杂功能：上一份要重发。
    fileprivate func watchChanged() {
        sent = nil
        sentUnread = nil
        Task { await sync() }
    }
    #else
    func activate(store: Store) {}
    func sync() async {}
    #endif
}

#if os(iOS)
extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in await self.sync() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// 换了一块手表：旧会话失效，重新激活才能给新手表发
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.watchChanged() }
    }
}
#endif
