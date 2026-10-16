#if DEBUG && os(iOS)
import SwiftUI
import UIKit

struct ReviewConnectionTestView: View {
    var body: some View { Color.clear.task { await ReviewConnectionSelfTest.run() } }
}

@MainActor enum ReviewConnectionSelfTest {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--review-self-test") }
    static func run() async {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("review-self-test")
        var checks: [String: Bool] = [:]
        var observations: [String: Any] = [:]
        let model = ReviewConnectionModel()
        do {
            let input = root.appendingPathComponent("input.json")
            let credential = try JSONDecoder().decode(ReviewConnection.Credentials.self, from: Data(contentsOf: input))
            try FileManager.default.removeItem(at: input)
            // The fixed runner creates a new simulator; these sentinels are synthetic local fixtures.
            let original = API.personal
            let sentinel = Data("isolated-personal-cache-fixture".utf8)
            original.cache.write(sentinel, for: "/review-isolation-sentinel")
            let privateDraft = ReviewConnection.draftKey("text", review: false)
            UserDefaults.standard.set("isolated-personal-draft-fixture", forKey: privateDraft)
            model.username = credential.username; model.password = credential.password
            await model.connect()
            checks["native.login_action"] = model.error == nil && !model.busy && model.password.isEmpty
            checks["native.active_review_api"] = API.shared === API.review && API.shared.reviewMode
            checks["native.keychain_roundtrip"] = ReviewConnection.credentials?.username == credential.username
                && ReviewConnection.credentials?.password == credential.password
            guard checks.values.allSatisfy({ $0 }) else { throw Gate.Failure(message: "review login failed") }
            checks["privacy.separate_cache"] = API.review.cache.dir != original.cache.dir
            checks["privacy.personal_cache_preserved"] = (try? Data(contentsOf: original.cache.dir.appendingPathComponent("_review-isolation-sentinel"))) == sentinel
            checks["privacy.personal_draft_preserved"] = UserDefaults.standard.string(forKey: privateDraft) == "isolated-personal-draft-fixture"
            checks["privacy.review_draft_separate"] = UserDefaults.standard.string(forKey: ReviewConnection.draftKey("text", review: true)) == nil
            let rejected = await API.review.fetch(URL(string: "https://day.tianli.cyou/api/index")!)
            if case .failure = rejected { checks["privacy.owner_api_rejected"] = true }
            else { checks["privacy.owner_api_rejected"] = false }
            let store = Store(api: API.review)
            await store.refresh()
            checks["cloud.index_and_open"] = store.indexError == nil && store.openError == nil && !store.index.isEmpty && !store.open.isEmpty
            observations["open_count"] = store.open.count
            guard let date = store.index.first?.date else { throw Gate.Failure(message: "review index empty") }
            let day = await store.day(date, force: true)
            checks["cloud.summary_and_timeline"] = day?.summary != nil && day?.items.isEmpty == false
            observations["timeline_count"] = day?.items.count ?? 0
            let text = "审核客户端隔离自检 " + UUID().uuidString
            let key = UUID().uuidString
            func saved(_ result: Result<Void, FeedError>) -> Bool { if case .success = result { return true }; return false }
            checks["cloud.note_receipt"] = saved(await Writer.note(text, date: date, idempotencyKey: key, api: API.review))
            checks["cloud.note_retry_receipt"] = saved(await Writer.note(text, date: date, idempotencyKey: key, api: API.review))
            let fresh = Store(api: API.review)
            let readback = await fresh.day(date, force: true)
            checks["cloud.fresh_store_note_once"] = readback?.cloudNotes.filter({ $0.text == text }).count == 1
            if let agenda = store.open.first {
                checks["cloud.agenda_done_receipt"] = saved(await Writer.mark(agenda.id, to: "done", title: agenda.title, api: API.review))
                await fresh.refresh()
                checks["cloud.agenda_done_readback"] = fresh.openError == nil && !fresh.open.contains(where: { $0.id == agenda.id })
                checks["cloud.agenda_restored"] = saved(await Writer.mark(agenda.id, to: "open", title: agenda.title, api: API.review))
            } else { checks["cloud.agenda_done_receipt"] = false }
            // Render the production Form after login, when credentials are no longer visible.
            let controller = UIHostingController(rootView: NavigationStack { Form { ReviewConnectionSection(model: model) } })
            let window = UIWindow(frame: CGRect(x: -10000, y: -10000, width: 430, height: 900))
            window.rootViewController = controller; window.isHidden = false
            controller.beginAppearanceTransition(true, animated: false); controller.endAppearanceTransition()
            controller.view.frame = CGRect(x: 0, y: 0, width: 430, height: 900)
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let png = image.pngData()
            checks["native.offscreen_form"] = (png?.count ?? 0) > 10000 && window.frame.maxX < 0 && !window.isKeyWindow
            window.isHidden = true
            try png?.write(to: root.appendingPathComponent("connected.png"))
            observations["rendered_width"] = 430; observations["rendered_height"] = 900
            let endpoint = URL(string: ReviewConnection.base + "/auth/session")!
            let oldCookie = API.review.session.configuration.httpCookieStorage?.cookies(for: endpoint)?
                .first(where: { $0.name == "notihub_review" })
            await model.returnToPersonal()
            checks["native.return_action"] = API.shared === original && !ReviewConnection.enabled
            checks["native.logout_action"] = model.error == nil && ReviewConnection.credentials == nil
                && (API.review.session.configuration.httpCookieStorage?.cookies(for: endpoint)?.isEmpty ?? true)
            // Replay the pre-logout cookie through a separate ephemeral session: a cleared local jar alone
            // cannot prove that the real server revoked the old session.
            let replay = ReviewConnection.session()
            defer { replay.invalidateAndCancel() }
            if let oldCookie {
                replay.configuration.httpCookieStorage?.setCookie(oldCookie)
                let (_, response) = try await replay.data(from: endpoint)
                checks["cloud.logout_revokes_old_session"] = (response as? HTTPURLResponse)?.statusCode == 401
            } else { checks["cloud.logout_revokes_old_session"] = false }
        } catch {
            checks["native.completed"] = false
            observations["error"] = "真实客户端审核连接自检未完成；不记录凭据或响应正文。"
            ReviewConnection.forget()
            ReviewConnection.clearCookies(session: API.review.session)
            ReviewConnection.activate(false)
        }
        let record: [String: Any] = ["checks": checks, "observations": observations,
                                    "environment": "dedicated iPhone simulator, real review HTTPS service",
                                    "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "",
                                    "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? ""]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: root.appendingPathComponent("result.json"), options: .atomic)
        }
        exit(!checks.isEmpty && checks.values.allSatisfy({ $0 }) ? 0 : 1)
    }
}
#endif
