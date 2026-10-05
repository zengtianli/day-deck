import XCTest
import Foundation
@testable import DayDeckCore

/// Serves a fixed body per path. Anything else is offline: no real network, no user data.
private final class CopyProtocol: URLProtocol {
    static let lock = NSLock()
    static var bodies: [String: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let body = Self.bodies[request.url?.path ?? ""]
        Self.lock.unlock()
        guard let body else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func serve(_ bodies: [String: Data]) {
        lock.lock(); Self.bodies = bodies; lock.unlock()
    }
}

/// Copy written in the backend's `ui.json` reaches `T("key", "built-in")` through the production
/// fetch, decode and cache path; a malformed `ui` costs only the overrides, never the index itself.
final class RemoteCopyTests: XCTestCase {
    private var directory: URL!
    private var session: URLSession!
    private var api: API!
    private let network = FeedError.network(url: "https://day.tianli.cyou/api/index", underlying: "offline")

    override func setUpWithError() throws {
        guard UserDefaults.standard.string(forKey: "gatepw")?.isEmpty != false else {
            throw NSError(domain: "RemoteCopy", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Run without a gatepw launch argument."])
        }
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("daydeck-copy-\(UUID())")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CopyProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        api = API(session: session, cacheDirectory: directory)
        CopyProtocol.serve([:])
        Remote.ui = nil
    }

    override func tearDownWithError() throws {
        Remote.ui = nil
        session?.invalidateAndCancel()
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }

    /// The shape `service/api.py` returns for `/api/index`; `ui` is whatever the case under test puts there.
    private func index(ui: Any?) -> Data {
        var body: [String: Any] = [
            "generatedAt": 1788714000, "lastSync": 1788714060, "timezone": "Asia/Shanghai",
            "days": [["date": "2026-09-07", "total": 3, "merged": 2, "headline": "A synthetic day",
                      "agendaOpen": 1, "whos": ["sender"]]],
        ]
        if let ui { body["ui"] = ui }
        return json(body)
    }

    private func serve(ui: Any?) {
        CopyProtocol.serve(["/api/index": index(ui: ui),
                            "/api/open": json(["generatedAt": 1788714000, "items": []])])
    }

    private let empty: [String: Any] = ["copy": [String: String](), "vocab": [String: Any](),
                                        "order": [String](), "limits": [String: Double]()]

    @MainActor
    func testBackendCopyReplacesBuiltInTextAfterFetchAndFromCache() async throws {
        serve(ui: ["copy": ["today.group.overdue": "拖过了", "error.network_advice": "先看看网络。"],
                   "vocab": [String: Any](), "order": [String](), "limits": [String: Double]()])
        let store = Store(api: api)
        XCTAssertEqual(T("today.group.overdue", "逾期"), "逾期")          // nothing fetched or cached yet
        await store.refresh()
        XCTAssertNil(store.indexError)
        XCTAssertEqual(store.index.first?.date, "2026-09-07")
        XCTAssertEqual(T("today.group.overdue", "逾期"), "拖过了")
        XCTAssertEqual(network.whatToDo, "先看看网络。")
        // Only the keys the backend wrote are replaced.
        XCTAssertEqual(T("today.group.today", "今天"), "今天")
        XCTAssertEqual(network.headline, "连不上 day 站")

        // A cold start offline reads the same overrides back from the cache.
        Remote.ui = nil
        CopyProtocol.serve([:])
        let cold = Store(api: api)
        XCTAssertEqual(cold.index.first?.date, "2026-09-07")
        XCTAssertEqual(T("today.group.overdue", "逾期"), "拖过了")
        XCTAssertEqual(network.whatToDo, "先看看网络。")
    }

    @MainActor
    func testMalformedUIDropsOnlyTheOverrides() async throws {
        let store = Store(api: api)
        let broken: [Any] = [
            "the whole section is a string",
            7,
            ["not", "an", "object"],
            ["copy": "a string where the table belongs"],
            ["copy": ["today.group.overdue": 5]],
            ["copy": ["today.group.overdue": "拖过了"], "limits": ["poll": "soon"]],
        ]
        for ui in broken {
            // A good document first: the broken one must also clear what was applied before it.
            serve(ui: ["copy": ["today.group.overdue": "拖过了"]])
            await store.refresh()
            XCTAssertEqual(T("today.group.overdue", "逾期"), "拖过了")

            serve(ui: ui)
            await store.refresh()
            XCTAssertNil(store.indexError, "\(ui)")
            XCTAssertEqual(store.index.first?.headline, "A synthetic day", "\(ui)")
            XCTAssertEqual(store.cloudTimezone.identifier, "Asia/Shanghai", "\(ui)")
            XCTAssertEqual(T("today.group.overdue", "逾期"), "逾期", "\(ui)")
            XCTAssertEqual(network.whatToDo, "请检查网络后重试；离线时仍可阅读上次缓存的记录。", "\(ui)")
        }
    }

    @MainActor
    func testMissingEmptyAndBlankOverridesKeepBuiltInText() async throws {
        let store = Store(api: api)
        for ui in [nil, NSNull(), empty, ["copy": ["today.group.overdue": ""]]] as [Any?] {
            serve(ui: ui)
            await store.refresh()
            XCTAssertNil(store.indexError)
            XCTAssertEqual(store.index.count, 1)
            XCTAssertEqual(T("today.group.overdue", "逾期"), "逾期")
            XCTAssertEqual(T("today.empty", "一条未完成的都没有。"), "一条未完成的都没有。")
            XCTAssertEqual(network.whatToDo, "请检查网络后重试；离线时仍可阅读上次缓存的记录。")
            XCTAssertEqual(FeedError.gate(url: "u", reason: "r").headline, "被访问闸拦住了")
        }
    }

    /// `ui` is decoration and forgiving; the fields the pages are built from still fail loudly.
    @MainActor
    func testBusinessFieldsOfTheIndexStayStrict() async throws {
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: index(ui: empty)) as? [String: Any])
        body.removeValue(forKey: "timezone")
        CopyProtocol.serve(["/api/index": json(body),
                            "/api/open": json(["generatedAt": 1788714000, "items": []])])
        let store = Store(api: api)
        await store.refresh()
        guard case .decoding(_, let field, _) = store.indexError else {
            return XCTFail("A missing business field must be reported, got \(String(describing: store.indexError))")
        }
        XCTAssertEqual(field, "timezone")
        XCTAssertTrue(store.index.isEmpty)
    }
}
