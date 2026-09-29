import Dependencies
import Foundation
import Testing
@testable import PointFreeKit

// SAFETY: тест обращается к объекту последовательно из одного таска; синхронизация не нужна.
private final class RequestLog: @unchecked Sendable { var requests: [URLRequest] = [] }

private func client(
  session: Session? = nil,
  log: RequestLog,
  respond: @escaping @Sendable (URLRequest) throws -> HTTPResponse
) -> PointFreeClient {
  withDependencies {
    $0.httpClient.fetch = { req in log.requests.append(req); return try respond(req) }
    $0.sessionStore.load = { session }
    $0.sessionStore.save = { _ in }
    $0.sessionStore.clear = { }
    $0.date.now = Date(timeIntervalSince1970: 1_000)
  } operation: {
    PointFreeClient.live(cache: MemoryCache(ttl: 60, maxEntries: 10, now: { Date(timeIntervalSince1970: 1_000) }))
  }
}

@Test func searchQueryEncodesSpecialCharacters() {
  let q = SearchQuery(query: "a & b + c #d", scope: .code, access: .free, sort: .newest)
  #expect(q.url.absoluteString == "https://www.pointfree.co/search?q=a%20%26%20b%20%2B%20c%20%23d&scope=code&access=free&sort=newest")
  #expect(SearchQuery(query: "x").url.absoluteString == "https://www.pointfree.co/search?q=x")
}

@Test func episodesDecodeAndAreCached() async throws {
  let log = RequestLog()
  let data = try fixture("episodes.json")
  let c = client(log: log) { _ in HTTPResponse(statusCode: 200, body: data) }
  let first = try await c.episodes()
  let second = try await c.episodes()
  #expect(first.count == 3 && second.count == 3)
  #expect(log.requests.count == 1)
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/api/episodes")
  #expect(log.requests[0].value(forHTTPHeaderField: "Cookie") == nil)
}

@Test func missingEpisodeIsNotFoundNotDecodingError() async throws {
  let log = RequestLog()
  let c = client(log: log) { _ in HTTPResponse(statusCode: 404, body: Data("<html>Page not found</html>".utf8)) }
  let missing = try #require(URL(string: "https://www.pointfree.co/api/episodes/9999"))
  await #expect(throws: PointFreeError.notFound(missing)) {
    _ = try await c.episode(9999)
  }
}

@Test func episodePageSendsCookieOnlyWhenSessionExists() async throws {
  let log = RequestLog()
  let session = Session(cookie: "COOKIE", expiresAt: Date(timeIntervalSince1970: 5_000), savedAt: Date(timeIntervalSince1970: 0))
  let c = client(session: session, log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<html></html>".utf8)) }
  _ = try await c.episodePage("ep381-x")
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/episodes/ep381-x")
  #expect(log.requests[0].value(forHTTPHeaderField: "Cookie") == "pf_session=COOKIE")

  let anon = client(log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<html></html>".utf8)) }
  _ = try await anon.episodePage("ep381-x")
  #expect(log.requests[1].value(forHTTPHeaderField: "Cookie") == nil)
}

@Test func expiredSessionIsNotSent() async throws {
  let log = RequestLog()
  let session = Session(cookie: "OLD", expiresAt: Date(timeIntervalSince1970: 500), savedAt: Date(timeIntervalSince1970: 0))
  let c = client(session: session, log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<html></html>".utf8)) }
  _ = try await c.episodePage("1")
  #expect(log.requests[0].value(forHTTPHeaderField: "Cookie") == nil)
}

@Test func validateSessionTreatsRedirectAsInvalid() async throws {
  let log = RequestLog()
  let c = client(log: log) { req in
    HTTPResponse(statusCode: req.value(forHTTPHeaderField: "Cookie") == "pf_session=GOOD" ? 200 : 302, body: Data())
  }
  #expect(try await c.validateSession("GOOD") == true)
  #expect(try await c.validateSession("BAD") == false)
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/account")
}

@Test func blogFeedIsFetchedFromAtomURL() async throws {
  let log = RequestLog()
  let c = client(log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<feed/>".utf8)) }
  #expect(try await c.blogFeed() == "<feed/>")
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/blog/feed/atom.xml")
}

@Test func serverErrorsSurfaceAsHttpStatus() async throws {
  let log = RequestLog()
  let c = client(log: log) { _ in HTTPResponse(statusCode: 503, body: Data()) }
  let collections = try #require(URL(string: "https://www.pointfree.co/collections"))
  await #expect(throws: PointFreeError.httpStatus(503, collections)) {
    _ = try await c.collectionsPage()
  }
}

@Test func blogPostPageIsFetchedWithoutCookieAndCached() async throws {
  let log = RequestLog()
  let session = Session(cookie: "COOKIE", expiresAt: Date(timeIntervalSince1970: 5_000), savedAt: Date(timeIntervalSince1970: 0))
  let c = client(session: session, log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<html><article></article></html>".utf8)) }
  _ = try await c.blogPostPage("228-lazystate-1-0-now-available-to-everyone")
  _ = try await c.blogPostPage("228-lazystate-1-0-now-available-to-everyone")
  #expect(log.requests.count == 1)
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone")
  #expect(log.requests[0].value(forHTTPHeaderField: "Cookie") == nil)
}
