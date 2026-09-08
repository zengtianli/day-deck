import Foundation

// =============================================================================
// 闸内取数的**唯一通路**（从 options-desk 的 DeskAPI 移植，契约 6）。
//
// 为什么抽出来：这个 app 有三个页面要取数（今天/复盘/日记），而 authgate 的
// 「撞闸 → 用钥匙串里的密码换会话 → 重试一次」如果在每个页面各写一份，就是三份
// 会各自漂移的判据。第一次改闸的行为（比如 cookie 名变了）就会有几页悄悄坏掉、
// 另几页还好着 —— 而且坏的那几页表现是「解码失败」，指向完全错误的方向。
// =============================================================================

/// 取数失败。**每个 case 都要能指出下一步动作** —— 没有 `whatToDo` 的错误提示等于没提示。
enum FeedError: Error, Equatable {
    case network(url: String, underlying: String)
    case http(url: String, status: Int, body: String)
    case decoding(url: String, field: String, detail: String)
    /// 被访问闸拦下。**必须单独一档** —— 它长得像成功（302 之后是登录页的 200 HTML），
    /// 混进 `.decoding` 就会显示成「服务返回的数据对不上契约」，把人引向服务端去查。
    case gate(url: String, reason: String)

    var headline: String {
        switch self {
        case .network:            return "连不上 day 站"
        case .http(_, let s, _):  return "站点返回 HTTP \(s)"
        case .decoding:           return "拿到的数据对不上契约"
        case .gate:               return "被访问闸拦住了"
        }
    }

    var detail: String {
        switch self {
        case .network(let url, let e):        return "\(url)\n\(e)"
        case .http(let url, let s, let body): return "\(url)\n状态 \(s)\n\(body.prefix(300))"
        case .decoding(let url, let f, let d): return "\(url)\n字段 `\(f)`\n\(d)"
        case .gate(let url, let r):           return "\(url)\n\(r)"
        }
    }

    var whatToDo: String {
        switch self {
        case .network:
            return "请检查网络后重试；离线时仍可阅读上次缓存的记录。"
        case .http(_, let s, _):
            return s == 404
                ? "云端还没有这一天的记录，请选择其他日期或稍后刷新。"
                : "云端暂时无法处理请求，请稍后重试。"
        case .decoding(_, let field, _):
            return "请更新应用后重试；不兼容的字段是 \(field)，上次可读记录仍保留。"
        case .gate:
            return "请在应用的连接设置中重新登录。"
        }
    }
}

final class API: @unchecked Sendable {
    static let shared = API()

    /// 数据源固定在 day 站。**不做可配置 base** —— 这个 app 只有这一个数据源，
    /// 留一个可配置项就多一处「配错了但看起来正常」的可能。
    let base = "https://day.tianli.cyou"
    let session: URLSession
    let cache: Cache

    init(session: URLSession? = nil, cacheDirectory: URL? = nil) {
        cache = Cache(directory: cacheDirectory)
        if let session { self.session = session; return }
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared          // 域 .tianli.cyou，跨启动保留，也跨子站共用
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 20
        // 站上是静态件，nginx 会给 ETag。但我们自己也缓存（见 Cache），
        // URLCache 只是省流量，**离线可读不能靠它**。
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: c)
    }

    /// 取原始字节。撞闸就换一次会话再重试**一次**（只一次：密码错的话无限重试
    /// 等于拿错密码反复撞限流，而界面上什么都看不出来）。
    func fetch(_ url: URL) async -> Result<Data, FeedError> {
        await request(URLRequest(url: url))
    }

    /// All cloud reads and writes share authentication and response validation.
    func request(_ request: URLRequest) async -> Result<Data, FeedError> {
        guard let url = request.url, url.scheme == "https", url.host == "day.tianli.cyou" else {
            return .failure(.network(url: base, underlying: "请求域名无效"))
        }
        let shown = url.absoluteString
        await Gate.seedFromLaunchArg(session: session)
        do {
            var (data, resp) = try await session.data(for: request)
            if Gate.blocked(resp) {
                guard let pw = Gate.password else {
                    return .failure(.gate(url: shown, reason: "这台设备还没有闸凭证（iOS 钥匙串里没有密码）"))
                }
                do { try await Gate.login(password: pw, session: session) }
                catch {
                    return .failure(.gate(url: shown,
                        reason: (error as? Gate.Failure)?.message ?? "登录失败"))
                }
                (data, resp) = try await session.data(for: request)
                if Gate.blocked(resp) {
                    return .failure(.gate(url: shown, reason: "拿密码换了会话之后仍被拦 —— 密码可能已经改了"))
                }
            }
            guard let http = resp as? HTTPURLResponse else {
                return .failure(.network(url: shown, underlying: "响应不是 HTTP"))
            }
            guard http.statusCode == 200 else {
                return .failure(.http(url: shown, status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "<非文本>"))
            }
            return .success(data)
        } catch {
            return .failure(.network(url: shown, underlying: (error as NSError).localizedDescription))
        }
    }

    /// 解码。**字段对不上就点名是哪个字段**，不容错、不填默认值 ——
    /// 容错会把「服务端契约漂了」变成「界面上静静显示一个错的东西」。
    func decode<T: Decodable>(_ data: Data, as type: T.Type, from shown: String) -> Result<T, FeedError> {
        do { return .success(try JSONDecoder().decode(T.self, from: data)) }
        catch let DecodingError.keyNotFound(key, ctx) {
            return .failure(.decoding(url: shown, field: key.stringValue, detail: ctx.debugDescription))
        }
        catch let DecodingError.typeMismatch(_, ctx) {
            return .failure(.decoding(url: shown,
                                      field: ctx.codingPath.map(\.stringValue).joined(separator: "."),
                                      detail: ctx.debugDescription))
        }
        catch let DecodingError.valueNotFound(_, ctx) {
            return .failure(.decoding(url: shown,
                                      field: ctx.codingPath.map(\.stringValue).joined(separator: "."),
                                      detail: "值是 null，但契约要求非空：" + ctx.debugDescription))
        }
        catch { return .failure(.decoding(url: shown, field: "(整个响应体)", detail: "\(error)")) }
    }

    /// 取 + 解码 + **落盘缓存**。缓存是这个 app 存在的理由之一（地铁里要能看），
    /// 所以它不是优化，是功能：网络失败时回落到上一次成功的那份，并告诉界面数据是什么时候的。
    func get<T: Decodable>(_ path: String, as type: T.Type) async -> (value: T?, error: FeedError?, cachedAt: Date?) {
        guard let url = URL(string: base + path) else {
            return (nil, .network(url: base + path, underlying: "URL 拼不出来"), nil)
        }
        switch await fetch(url) {
        case .success(let data):
            switch decode(data, as: T.self, from: url.absoluteString) {
            case .success(let v):
                guard !Task.isCancelled else { return (nil, nil, nil) }
                cache.write(data, for: path)
                return (v, nil, Date())
            case .failure(let e):
                // 解码失败**不覆盖缓存** —— 拿一份坏数据换掉能用的旧数据是净损失。
                return (cache.load(path, as: T.self, api: self)?.0, e, cache.stamp(path))
            }
        case .failure(let e):
            if let (v, at) = cache.load(path, as: T.self, api: self) { return (v, e, at) }
            return (nil, e, nil)
        }
    }
}

/// 落盘缓存。放 Application Support（不是 Caches）—— 系统可以随时清空 Caches，
/// 而「地铁里打开还能看昨天」正是这个 app 的用途，被清空就等于功能没了。
struct Cache {
    let dir: URL
    init(directory: URL? = nil) {
        dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("feed-vps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ path: String) -> URL {
        // path 形如 "/2026-08-30.json"，去掉前导斜杠即可当文件名（站上是平铺的）
        dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }

    func write(_ data: Data, for path: String) {
        try? data.write(to: file(path), options: .atomic)
    }

    func stamp(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: file(path).path)[.modificationDate] as? Date
    }

    func load<T: Decodable>(_ path: String, as type: T.Type, api: API) -> (T, Date)? {
        guard let d = try? Data(contentsOf: file(path)),
              case .success(let v) = api.decode(d, as: T.self, from: "cache:" + path),
              let at = stamp(path) else { return nil }
        return (v, at)
    }

    /// Keep the last readable copy; mark it stale so writes are followed by a real fetch.
    func invalidate(_ path: String) {
        guard FileManager.default.fileExists(atPath: file(path).path) else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: file(path).path)
    }
}
