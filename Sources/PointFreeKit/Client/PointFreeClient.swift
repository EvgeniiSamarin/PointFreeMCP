import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct PointFreeClient: Sendable {
  public var episodes: @Sendable () async throws -> [EpisodeSummary]
  public var episode: @Sendable (_ id: Int) async throws -> EpisodeDetail
  public var episodePage: @Sendable (_ pathComponent: String) async throws -> String
  public var search: @Sendable (_ query: SearchQuery) async throws -> String
  public var collectionsPage: @Sendable () async throws -> String
  public var collectionPage: @Sendable (_ slug: String) async throws -> String
  public var sectionPage: @Sendable (_ slug: String, _ section: String) async throws -> String
  public var blogFeed: @Sendable () async throws -> String
  public var blogPostPage: @Sendable (_ pathComponent: String) async throws -> String
  public var validateSession: @Sendable (_ cookie: String) async throws -> Bool
  public var invalidateCache: @Sendable () async -> Void
}

extension PointFreeClient {
  public static let baseURL: URL = {
    guard let url = URL(string: "https://www.pointfree.co") else { preconditionFailure("invalid base URL") }
    return url
  }()
  public static let cookieName = "pf_session"

  public static func live(cache: MemoryCache<String>) -> PointFreeClient {
    // Зависимости захватываются в момент создания клиента и биндятся в let,
    // чтобы @Sendable-замыкания не захватывали var.
    @Dependency(\.httpClient) var httpDependency
    @Dependency(\.sessionStore) var sessionStoreDependency
    @Dependency(\.date) var dateDependency
    let http = httpDependency
    let sessionStore = sessionStoreDependency
    let date = dateDependency

    @Sendable func currentCookie() -> String? {
      guard let session = try? sessionStore.load(), !session.isExpired(now: date.now) else { return nil }
      return session.cookie
    }

    /// GET с cookie (если есть), 404 -> notFound, 3xx/4xx/5xx -> httpStatus.
    @Sendable func get(_ path: String, query: [URLQueryItem] = [], url overrideURL: URL? = nil, cookie: String?) async throws -> HTTPResponse {
      let url: URL
      if let overrideURL { url = overrideURL } else {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
          throw PointFreeError.network("invalid URL for \(path)")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let built = components.url else { throw PointFreeError.network("invalid URL for \(path)") }
        url = built
      }
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
      if let cookie, url.host == baseURL.host {
        request.setValue("\(cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
      }
      let response = try await http.fetch(request)
      switch response.statusCode {
      case 200: return response
      case 404: throw PointFreeError.notFound(url)
      default: throw PointFreeError.httpStatus(response.statusCode, url)
      }
    }

    @Sendable func cachedHTML(key: String, _ load: @Sendable () async throws -> HTTPResponse) async throws -> String {
      if let hit = await cache.value(for: key) { return hit }
      let html = String(decoding: try await load().body, as: UTF8.self)
      await cache.set(html, for: key)
      return html
    }

    return PointFreeClient(
      episodes: {
        let key = "api/episodes"
        if let hit = await cache.value(for: key), let data = hit.data(using: .utf8) {
          return try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: data)
        }
        let response = try await get("api/episodes", cookie: nil)
        do {
          let episodes = try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: response.body)
          await cache.set(String(decoding: response.body, as: UTF8.self), for: key)
          return episodes
        } catch {
          throw PointFreeError.decoding("episodes: \(error)")
        }
      },
      episode: { id in
        let response = try await get("api/episodes/\(id)", cookie: nil)
        do { return try PointFreeJSON.decoder.decode(EpisodeDetail.self, from: response.body) }
        catch { throw PointFreeError.decoding("episode \(id): \(error)") }
      },
      episodePage: { pathComponent in
        let cookie = currentCookie()
        let key = "episode/\(pathComponent)/\(cookie == nil ? "anon" : "auth")"
        return try await cachedHTML(key: key) { try await get("episodes/\(pathComponent)", cookie: cookie) }
      },
      search: { query in
        try await cachedHTML(key: "search/\(query.cacheKey)") { try await get("", url: query.url, cookie: nil) }
      },
      collectionsPage: {
        try await cachedHTML(key: "collections") { try await get("collections", cookie: nil) }
      },
      collectionPage: { slug in
        try await cachedHTML(key: "collections/\(slug)") { try await get("collections/\(slug)", cookie: nil) }
      },
      sectionPage: { slug, section in
        try await cachedHTML(key: "collections/\(slug)/\(section)") { try await get("collections/\(slug)/\(section)", cookie: nil) }
      },
      blogFeed: {
        try await cachedHTML(key: "blog/feed/atom.xml") { try await get("blog/feed/atom.xml", cookie: nil) }
      },
      blogPostPage: { pathComponent in
        try await cachedHTML(key: "blog/posts/\(pathComponent)") { try await get("blog/posts/\(pathComponent)", cookie: nil) }
      },
      validateSession: { cookie in
        // 200 — сессия принята; редирект (на /login) или 401/403 — отвергнута;
        // прочие коды (5xx, 429, …) ничего не говорят о cookie и выбрасываются как ошибка.
        let url = baseURL.appendingPathComponent("account")
        var request = URLRequest(url: url)
        request.setValue("\(cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
        let response = try await http.fetch(request)
        switch response.statusCode {
        case 200: return true
        case 300..<400, 401, 403: return false
        default: throw PointFreeError.httpStatus(response.statusCode, url)
        }
      },
      invalidateCache: { await cache.removeAll() }
    )
  }
}

extension PointFreeClient: DependencyKey {
  public static let liveValue = PointFreeClient.live(cache: MemoryCache(ttl: 60 * 60, maxEntries: 50))
}

extension DependencyValues {
  public var pointFreeClient: PointFreeClient {
    get { self[PointFreeClient.self] }
    set { self[PointFreeClient.self] = newValue }
  }
}
