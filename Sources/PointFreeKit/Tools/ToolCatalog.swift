import Dependencies
import Foundation

public struct ToolOutput: Equatable, Sendable {
  public var text: String
  public var isError: Bool
  public init(text: String, isError: Bool = false) { self.text = text; self.isError = isError }
}

public struct ToolCatalog: Sendable {
  @Dependency(\.pointFreeClient) var client
  @Dependency(\.sessionStore) var sessionStore
  @Dependency(\.loginLauncher) var loginLauncher
  @Dependency(\.date.now) var now

  public init() {}

  public func call(name: String, arguments: ToolArguments) async -> ToolOutput {
    do {
      switch name {
      case "searchPointFree": return try await search(arguments)
      case "fetchEpisode": return try await fetchEpisode(arguments)
      case "listEpisodes": return try await listEpisodes(arguments)
      case "fetchCollection": return try await fetchCollection(arguments)
      case "listBlogPosts": return try await listBlogPosts(arguments)
      case "fetchBlogPost": return try await fetchBlogPost(arguments)
      case "login": return try await login(arguments)
      default: return ToolOutput(text: "Unknown tool: \(name)", isError: true)
      }
    } catch let error as PointFreeError {
      return ToolOutput(text: error.userMessage, isError: true)
    } catch {
      return ToolOutput(text: "Unexpected error: \(error)", isError: true)
    }
  }

  func search(_ args: ToolArguments) async throws -> ToolOutput {
    guard let query = args.string("query") else { throw PointFreeError.invalidArgument("`query` is required") }
    let scope = try enumArg(args, "scope", SearchQuery.Scope.self)
    let access = try enumArg(args, "access", SearchQuery.Access.self)
    let sort = try enumArg(args, "sort", SearchQuery.Sort.self)
    let q = SearchQuery(query: query, scope: scope, access: access, sort: sort)
    let html = try await client.search(q)
    let page = try SearchPageParser.parse(html: html, url: q.url)
    let episodes = (try? await client.episodes()) ?? []
    let byID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
    return ToolOutput(text: MarkdownRenderer.search(query: q, page: page, episodes: byID))
  }

  func fetchEpisode(_ args: ToolArguments) async throws -> ToolOutput {
    guard let raw = args.string("episode") else { throw PointFreeError.invalidArgument("`episode` is required") }
    guard var ref = EpisodeRef.parse(raw) else {
      throw PointFreeError.invalidArgument("`episode` must be a number (381), a slug (ep381-…) or a pointfree.co episode URL; got \"\(raw)\"")
    }
    if let sectionText = args.string("section") { ref.section = SectionRef.parse(sectionText) }

    let detail = try await client.episode(ref.number)
    let html = try await client.episodePage(ref.pathComponent)
    let page = try EpisodePageParser.parse(html: html, url: detail.pageURL)

    if page.isTruncated && detail.subscriberOnly {
      guard let session = try sessionStore.load() else { throw PointFreeError.loginRequired }
      if session.isExpired(now: now) {
        try sessionStore.clear()
        throw PointFreeError.sessionExpired
      }
      if try await client.validateSession(session.cookie) {
        throw PointFreeError.subscriptionRequired
      } else {
        try sessionStore.clear()
        await client.invalidateCache()
        throw PointFreeError.sessionExpired
      }
    }
    if !page.transcript.hasBody {
      throw PointFreeError.structureChanged("transcript body", detail.pageURL)
    }
    return ToolOutput(text: try MarkdownRenderer.episode(detail: detail, transcript: page.transcript, section: ref.section))
  }

  func listEpisodes(_ args: ToolArguments) async throws -> ToolOutput {
    let limit = max(1, args.int("limit") ?? 50)
    var episodes = try await client.episodes().sorted { $0.sequence > $1.sequence }
    if let filter = args.string("filter")?.lowercased() {
      episodes = episodes.filter { $0.title.lowercased().contains(filter) }
    }
    return ToolOutput(text: MarkdownRenderer.episodeList(Array(episodes.prefix(limit))))
  }

  func fetchCollection(_ args: ToolArguments) async throws -> ToolOutput {
    guard let slug = args.string("slug")?.lowercased() else {
      let list = try CollectionsParser.parseIndex(html: try await client.collectionsPage())
      return ToolOutput(text: MarkdownRenderer.collections(list))
    }
    guard let section = args.string("section")?.lowercased() else {
      let c = try CollectionsParser.parseCollection(html: try await client.collectionPage(slug), slug: slug)
      return ToolOutput(text: MarkdownRenderer.collection(title: c.title, slug: slug, sections: c.sections))
    }
    let s = try CollectionsParser.parseSection(html: try await client.sectionPage(slug, section))
    return ToolOutput(text: MarkdownRenderer.section(collectionSlug: slug, sectionSlug: section, title: s.title, groups: s.groups))
  }

  func listBlogPosts(_ args: ToolArguments) async throws -> ToolOutput {
    let limit = max(1, args.int("limit") ?? 30)
    var posts = try BlogFeedParser.parse(xml: try await client.blogFeed()).sorted { $0.number > $1.number }
    if let filter = args.string("filter")?.lowercased() {
      posts = posts.filter { $0.title.lowercased().contains(filter) }
    }
    return ToolOutput(text: MarkdownRenderer.blogList(Array(posts.prefix(limit))))
  }

  func fetchBlogPost(_ args: ToolArguments) async throws -> ToolOutput {
    guard let raw = args.string("post") else { throw PointFreeError.invalidArgument("`post` is required") }
    guard let ref = BlogPostRef.parse(raw) else {
      throw PointFreeError.invalidArgument("`post` must be a number (228), a slug (228-…) or a pointfree.co blog URL; got \"\(raw)\"")
    }
    let posts = try BlogFeedParser.parse(xml: try await client.blogFeed())
    guard let post = posts.first(where: { $0.number == ref.number }) else {
      throw PointFreeError.invalidArgument("Blog post \(ref.number) not found in the feed")
    }
    let html = try await client.blogPostPage(post.slug)
    let blocks = try BlogContentParser.blocks(page: html, url: post.url)
    return ToolOutput(text: MarkdownRenderer.blogPost(post, blocks: blocks))
  }

  func login(_ args: ToolArguments) async throws -> ToolOutput {
    let force = args.bool("force") ?? false
    if !force, let session = try sessionStore.load(), !session.isExpired(now: now),
       try await client.validateSession(session.cookie) {
      let days = Int(session.expiresAt.timeIntervalSince(now) / 86_400)
      return ToolOutput(text: "Already signed in to pointfree.co. Session valid until \(session.expiresAt) (about \(days) more day(s)). Pass force=true to sign in again.")
    }
    switch try await loginLauncher.run() {
    case .success:
      await client.invalidateCache()
      guard let saved = try sessionStore.load() else {
        return ToolOutput(text: PointFreeError.loginFailed("login finished but no session was saved").userMessage, isError: true)
      }
      return ToolOutput(text: "Signed in to pointfree.co. Session valid until \(saved.expiresAt). Members-only transcripts are now available; retry your request.")
    case .cancelled:
      return ToolOutput(text: "Login was cancelled (the window was closed before signing in).", isError: true)
    case .failed(let message):
      return ToolOutput(text: PointFreeError.loginFailed(message).userMessage, isError: true)
    }
  }

  private func enumArg<T: RawRepresentable & CaseIterable>(_ args: ToolArguments, _ key: String, _ type: T.Type) throws -> T? where T.RawValue == String {
    guard let raw = args.string(key) else { return nil }
    guard let value = T(rawValue: raw.lowercased()) else {
      let allowed = T.allCases.map { "\($0.rawValue)" }.joined(separator: ", ")
      throw PointFreeError.invalidArgument("`\(key)` must be one of: \(allowed); got \"\(raw)\"")
    }
    return value
  }
}
