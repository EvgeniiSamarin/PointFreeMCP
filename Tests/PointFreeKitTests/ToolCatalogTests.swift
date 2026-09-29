import Dependencies
import Foundation
import Testing
@testable import PointFreeKit

private func args(_ json: String) throws -> ToolArguments {
  try JSONDecoder().decode(ToolArguments.self, from: Data(json.utf8))
}

private func detailJSON() throws -> EpisodeDetail {
  try PointFreeJSON.decoder.decode(EpisodeDetail.self, from: fixture("episode-381.json"))
}

// SAFETY: тест обращается к объекту последовательно из одного таска; синхронизация не нужна.
private final class Flag: @unchecked Sendable { var value = false }

@Test func toolDefinitionsAreValidJSONSchemas() throws {
  #expect(ToolDefinitions.all.map(\.name) == ["searchPointFree", "fetchEpisode", "listEpisodes", "fetchCollection", "listBlogPosts", "fetchBlogPost", "login"])
  for def in ToolDefinitions.all {
    let obj = try JSONSerialization.jsonObject(with: Data(def.inputSchemaJSON.utf8)) as? [String: Any]
    #expect(obj?["type"] as? String == "object", "\(def.name)")
    #expect(obj?["properties"] is [String: Any], "\(def.name)")
  }
}

@Test func toolArgumentsDecodeMixedTypes() throws {
  let a = try args(#"{"query":"x","limit":5,"force":true,"ratio":2.0}"#)
  #expect(a.string("query") == "x")
  #expect(a.int("limit") == 5)
  #expect(a.int("ratio") == 2)
  #expect(a.bool("force") == true)
  #expect(a.string("missing") == nil)
}

@Test func toolArgumentsIntDoesNotTrapOnHugeDoubles() throws {
  let a = try args(#"{"limit":1e30,"frac":2.5,"ok":2.0}"#)
  #expect(a.int("limit") == nil)
  #expect(a.int("frac") == nil)
  #expect(a.int("ok") == 2)
}

@Test func searchToolRendersResults() async throws {
  let out = try await withDependencies {
    $0.pointFreeClient.search = { q in
      #expect(q == SearchQuery(query: "Sendable", scope: .dialogue, access: nil, sort: nil))
      return try fixtureString("search.html")
    }
    $0.pointFreeClient.episodes = { try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: fixture("episodes.json")) }
  } operation: {
    await ToolCatalog().call(name: "searchPointFree", arguments: try args(#"{"query":"Sendable","scope":"dialogue"}"#))
  }
  #expect(!out.isError)
  #expect(out.text.contains("## #381: Designing for Isolation: Naively (Members only)"))
}

@Test func searchToolRejectsBadScope() async throws {
  let out = await ToolCatalog().call(name: "searchPointFree", arguments: try args(#"{"query":"x","scope":"everything"}"#))
  #expect(out.isError)
  #expect(out.text.contains("scope"))
}

@Test func fetchEpisodeRendersTranscript() async throws {
  let out = try await withDependencies {
    $0.pointFreeClient.episode = { id in #expect(id == 381); return try detailJSON() }
    $0.pointFreeClient.episodePage = { path in #expect(path == "381"); return try fixtureString("episode-free.html") }
  } operation: {
    await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"381"}"#))
  }
  #expect(!out.isError)
  #expect(out.text.contains("# Episode #381"))
  #expect(out.text.contains("## Introduction"))
}

@Test func fetchEpisodeWithoutSessionAsksToLogin() async throws {
  let out = try await withDependencies {
    $0.pointFreeClient.episode = { _ in try detailJSON() }
    $0.pointFreeClient.episodePage = { _ in try fixtureString("episode-locked.html") }
    $0.sessionStore.load = { nil }
  } operation: {
    await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"ep381-designing-for-isolation-naively"}"#))
  }
  #expect(out.isError)
  #expect(out.text == PointFreeError.loginRequired.userMessage)
}

@Test func fetchEpisodeWithDeadSessionClearsItAndAsksToLogin() async throws {
  let flag = Flag()
  let out = try await withDependencies {
    $0.pointFreeClient.episode = { _ in try detailJSON() }
    $0.pointFreeClient.episodePage = { _ in try fixtureString("episode-locked.html") }
    $0.pointFreeClient.validateSession = { _ in false }
    $0.sessionStore.load = { Session(cookie: "OLD", expiresAt: .distantFuture, savedAt: .distantPast) }
    $0.sessionStore.clear = { flag.value = true }
    $0.date.now = Date()
  } operation: {
    await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"381"}"#))
  }
  #expect(out.isError)
  #expect(out.text == PointFreeError.sessionExpired.userMessage)
  #expect(flag.value)
}

@Test func fetchEpisodeWithValidSessionButTruncatedKeepsSession() async throws {
  let flag = Flag()
  let out = try await withDependencies {
    $0.pointFreeClient.episode = { _ in try detailJSON() }
    $0.pointFreeClient.episodePage = { _ in try fixtureString("episode-locked.html") }
    $0.pointFreeClient.validateSession = { _ in true }
    $0.sessionStore.load = { Session(cookie: "OK", expiresAt: .distantFuture, savedAt: .distantPast) }
    $0.sessionStore.clear = { flag.value = true }
    $0.date.now = Date()
  } operation: {
    await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"381"}"#))
  }
  #expect(out.isError)
  #expect(out.text == PointFreeError.subscriptionRequired.userMessage)
  #expect(!flag.value)
}

@Test func fetchEpisodeRejectsBadReference() async throws {
  let out = await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"functions"}"#))
  #expect(out.isError)
  #expect(out.text.contains("episode"))
}

@Test func listEpisodesFiltersAndLimits() async throws {
  let out = try await withDependencies {
    $0.pointFreeClient.episodes = { try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: fixture("episodes.json")) }
  } operation: {
    await ToolCatalog().call(name: "listEpisodes", arguments: try args(#"{"filter":"isolation","limit":10}"#))
  }
  #expect(out.text.contains("#381"))
  #expect(!out.text.contains("#379"))
}

@Test func fetchCollectionDispatchesByArguments() async throws {
  let catalog = ToolCatalog()
  let index = try await withDependencies {
    $0.pointFreeClient.collectionsPage = { try fixtureString("collections.html") }
  } operation: { await catalog.call(name: "fetchCollection", arguments: try args("{}")) }
  #expect(index.text.contains("`composable-architecture`"))

  let sections = try await withDependencies {
    $0.pointFreeClient.collectionPage = { slug in #expect(slug == "composable-architecture"); return try fixtureString("collection.html") }
  } operation: { await catalog.call(name: "fetchCollection", arguments: try args(#"{"slug":"composable-architecture"}"#)) }
  #expect(sections.text.contains("`testing`"))

  let episodes = try await withDependencies {
    $0.pointFreeClient.sectionPage = { slug, section in #expect(slug == "composable-architecture" && section == "testing"); return try fixtureString("section.html") }
  } operation: { await catalog.call(name: "fetchCollection", arguments: try args(#"{"slug":"composable-architecture","section":"testing"}"#)) }
  #expect(episodes.text.contains("#82"))
}

@Test func blogToolsListFromFeedAndFetchFromPage() async throws {
  let catalog = ToolCatalog()
  let list = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
  } operation: { await catalog.call(name: "listBlogPosts", arguments: try args(#"{"filter":"lazystate","limit":5}"#)) }
  #expect(!list.isError)
  #expect(list.text.contains("#228 LazyState 1.0"))
  #expect(!list.text.contains("#1 Announcing"))

  let post = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
    $0.pointFreeClient.blogPostPage = { path in
      #expect(path == "228-lazystate-1-0-now-available-to-everyone")
      return try fixtureString("blog-post.html")
    }
  } operation: { await catalog.call(name: "fetchBlogPost", arguments: try args(#"{"post":"228"}"#)) }
  #expect(!post.isError)
  #expect(post.text.hasPrefix("# LazyState 1.0: Now available to everyone"))
  #expect(post.text.contains("```swift\n@LazyState var model = Model()\n```"))
  #expect(post.text.contains("- Published: 2026-09-14"))

  let missing = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
  } operation: { await catalog.call(name: "fetchBlogPost", arguments: try args(#"{"post":"999"}"#)) }
  #expect(missing.isError)
  #expect(missing.text.contains("999"))
}

@Test func loginToolReportsExistingValidSession() async throws {
  let out = try await withDependencies {
    $0.sessionStore.load = { Session(cookie: "OK", expiresAt: Date(timeIntervalSince1970: 200), savedAt: Date(timeIntervalSince1970: 0)) }
    $0.pointFreeClient.validateSession = { _ in true }
    $0.date.now = Date(timeIntervalSince1970: 100)
    $0.loginLauncher.run = { Issue.record("must not launch"); return .cancelled }
  } operation: { await ToolCatalog().call(name: "login", arguments: try args("{}")) }
  #expect(!out.isError)
  #expect(out.text.contains("Already signed in"))
}

@Test func loginToolLaunchesWindowAndInvalidatesCache() async throws {
  let flag = Flag()
  let out = try await withDependencies {
    $0.sessionStore.load = { flag.value ? Session(cookie: "NEW", expiresAt: .distantFuture, savedAt: .distantPast) : nil }
    $0.loginLauncher.run = { .success }
    $0.pointFreeClient.invalidateCache = { flag.value = true }
  } operation: { await ToolCatalog().call(name: "login", arguments: try args("{}")) }
  #expect(!out.isError)
  #expect(out.text.contains("Signed in"))
  #expect(flag.value)
}

@Test func loginToolReportsCancellation() async throws {
  let out = try await withDependencies {
    $0.sessionStore.load = { nil }
    $0.loginLauncher.run = { .cancelled }
  } operation: { await ToolCatalog().call(name: "login", arguments: try args("{}")) }
  #expect(out.isError)
  #expect(out.text.contains("cancelled"))
}

@Test func unknownToolIsError() async throws {
  let out = await ToolCatalog().call(name: "nope", arguments: try args("{}"))
  #expect(out.isError)
}
