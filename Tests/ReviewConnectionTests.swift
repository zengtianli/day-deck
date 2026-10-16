import XCTest
import Foundation
@testable import DayDeckCore

private final class ReviewProtocol: URLProtocol {
    static var requests: [URLRequest] = []
    static var reply = Data("{\"ok\":true,\"scope\":\"synthetic-review\",\"apiBase\":\"/review\"}".utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.reply)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ReviewConnectionTests: XCTestCase {
    func testReviewAndPersonalRequestsCannotCrossRealms() {
        for path in ["/review/api/index", "/review/api/open", "/review/auth/login"] {
            let url = URL(string: "https://day.tianli.cyou" + path)!
            XCTAssertTrue(ReviewConnection.allows(url, review: true))
            XCTAssertFalse(ReviewConnection.allows(url, review: false))
        }
        let personal = URL(string: "https://day.tianli.cyou/api/index")!
        XCTAssertFalse(ReviewConnection.allows(personal, review: true))
        XCTAssertTrue(ReviewConnection.allows(personal, review: false))
        for raw in ["http://day.tianli.cyou/review/api/index", "https://other.invalid/review/api/index",
                    "https://user:secret@day.tianli.cyou/review/api/index", "https://day.tianli.cyou/reviewer/api/index",
                    "https://day.tianli.cyou/review/../api/index"] {
            XCTAssertFalse(ReviewConnection.allows(URL(string: raw)!, review: true))
        }
    }

    func testReviewDraftsDoNotUseTheOwnersExistingKeys() {
        for field in ["text", "date", "key"] {
            XCTAssertEqual(ReviewConnection.draftKey(field, review: false), "diary.cloudDraft." + field)
            XCTAssertNotEqual(ReviewConnection.draftKey(field, review: true), ReviewConnection.draftKey(field, review: false))
        }
    }

    func testCrossRealmRequestIsRejectedBeforeAnyTransport() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewProtocol.self]
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = API(session: session, cacheDirectory: directory, reviewMode: true)
        ReviewProtocol.requests = []
        let result = await api.fetch(URL(string: "https://day.tianli.cyou/api/index")!)
        if case .success = result { XCTFail("review client reached owner API") }
        XCTAssertTrue(ReviewProtocol.requests.isEmpty)
        XCTAssertEqual(api.base, ReviewConnection.base)
    }

    func testAnOKBodyWithoutScopedCookieIsNotAuthenticated() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewProtocol.self]
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        ReviewProtocol.requests = []
        do {
            try await ReviewConnection.login(username: "synthetic-reviewer", password: "synthetic-test-only", session: session)
            XCTFail("body without authenticated cookie was accepted")
        } catch {}
        XCTAssertEqual(ReviewProtocol.requests.count, 1)
        XCTAssertEqual(ReviewProtocol.requests.first?.url?.path, "/review/auth/login")
        XCTAssertNil(ReviewProtocol.requests.first?.url?.query)
    }

    func testReviewWritesUseTheNamespaceAndRootOrigin() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewProtocol.self]
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = API(session: session, cacheDirectory: directory, reviewMode: true)
        let old = ReviewProtocol.reply
        defer { ReviewProtocol.reply = old }
        ReviewProtocol.reply = Data("{\"id\":91,\"text\":\"synthetic note\",\"date\":\"2026-10-16\",\"ts\":1788714000}".utf8)
        ReviewProtocol.requests = []
        let result = await Writer.note("synthetic note", date: "2026-10-16", idempotencyKey: "synthetic-unique-id", api: api)
        if case .failure(let error) = result { XCTFail("unexpected failure: \(error)") }
        XCTAssertEqual(ReviewProtocol.requests.count, 1)
        XCTAssertEqual(ReviewProtocol.requests.first?.url?.path, "/review/api/notes")
        XCTAssertEqual(ReviewProtocol.requests.first?.value(forHTTPHeaderField: "Origin"), "https://day.tianli.cyou")
    }

    func testLogoutUsesTheAuthenticatedReviewEndpoint() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewProtocol.self]
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        ReviewProtocol.requests = []
        try await ReviewConnection.logout(session: session)
        XCTAssertEqual(ReviewProtocol.requests.count, 1)
        let request = try XCTUnwrap(ReviewProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/review/auth/logout")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://day.tianli.cyou")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Notifhub-Request"), "1")
    }
}
