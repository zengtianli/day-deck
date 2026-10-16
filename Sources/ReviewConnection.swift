import Foundation

/// The review service is a separate authenticated server instance, not a local demo bypass.
enum ReviewConnection {
    static let base = "https://day.tianli.cyou/review"
    static let changed = Notification.Name("NotihubConnectionChanged")
    private static let modeKey = "cloud.reviewConnection"
    private static let credentialService = "cyou.tianli.daydeck.review"
    struct Credentials: Codable { let username: String; let password: String }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: modeKey) }
    static func activate(_ review: Bool) {
        UserDefaults.standard.set(review, forKey: modeKey)
        NotificationCenter.default.post(name: changed, object: nil)
    }
    static func draftKey(_ name: String, review: Bool) -> String {
        (review ? "review." : "") + "diary.cloudDraft." + name
    }
    static var credentials: Credentials? {
        guard let value = Gate.credential(service: credentialService, account: "login"),
              let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }
    static func remember(username: String, password: String) -> Bool {
        guard let data = try? JSONEncoder().encode(Credentials(username: username, password: password)),
              let value = String(data: data, encoding: .utf8) else { return false }
        return Gate.saveCredential(value, service: credentialService, account: "login")
    }
    static func forget() {
        Gate.forgetCredential(service: credentialService, account: "login")
    }
    static func clearCookies(session: URLSession) {
        let jar = session.configuration.httpCookieStorage
        for cookie in jar?.cookies ?? [] { jar?.deleteCookie(cookie) }
    }
    static func logout(session: URLSession) async throws {
        defer { clearCookies(session: session) }
        let endpoint = URL(string: base + "/auth/logout")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://day.tianli.cyou", forHTTPHeaderField: "Origin")
        request.setValue("1", forHTTPHeaderField: "X-Notifhub-Request")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await session.data(for: request)
        let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.url == endpoint,
              value?["ok"] as? Bool == true else {
            throw Gate.Failure(message: "本机已退出审核连接；服务端会话撤销尚未确认，请稍后重新连接后退出。")
        }
    }
    static func allows(_ url: URL, review: Bool) -> Bool {
        guard url.scheme == "https", url.host == "day.tianli.cyou", url.user == nil,
              url.password == nil, url.port == nil, url.fragment == nil,
              !url.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        let isReview = url.path == "/review" || url.path.hasPrefix("/review/")
        return review == isReview
    }
    static func session() -> URLSession {
        // Ephemeral storage never receives the owner's shared authgate cookies.
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: NoReviewRedirects(), delegateQueue: nil)
    }
    static func login(username: String, password: String, session: URLSession) async throws {
        guard !username.isEmpty, username.count <= 64, !password.isEmpty, password.count <= 256 else {
            throw Gate.Failure(message: "请输入专用审核账号和密码。")
        }
        let endpoint = URL(string: base + "/auth/login")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Credentials(username: username, password: password))
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, response.url == endpoint, value?["ok"] as? Bool == true,
              value?["scope"] as? String == "synthetic-review", value?["apiBase"] as? String == "/review",
              session.configuration.httpCookieStorage?.cookies(for: endpoint)?.contains(where: {
                  $0.name == "notihub_review" && $0.domain == "day.tianli.cyou" && $0.path == "/review/" && $0.isSecure
              }) == true else {
            throw Gate.Failure(message: "审核服务登录未完成（HTTP \(status)）；请核对专用账号或稍后重试。")
        }
    }
}

private final class NoReviewRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
