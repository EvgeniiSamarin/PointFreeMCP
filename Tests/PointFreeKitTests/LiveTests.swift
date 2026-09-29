import Dependencies
import Foundation
import Testing
@testable import PointFreeKit

private let live = ProcessInfo.processInfo.environment["POINTFREE_LIVE"] == "1"

/// Живые зависимости: в тестовом контексте swift-dependencies без явного `.live` подставляет unimplemented-значения.
private func liveClient() -> PointFreeClient {
  withDependencies { $0.context = .live } operation: { PointFreeClient.live(cache: MemoryCache(ttl: 60, maxEntries: 5)) }
}

@Test(.enabled(if: live)) func liveSearchAndFreeEpisode() async throws {
  let client = liveClient()
  let episodes = try await client.episodes()
  #expect(episodes.count > 300)
  #expect(episodes.allSatisfy { $0.id == $0.sequence })  // fetchEpisode использует номер как id

  let html = try await client.search(SearchQuery(query: "Sendable", scope: .dialogue))
  let search = try SearchPageParser.parse(html: html, url: nil)
  #expect(!search.results.isEmpty)
  #expect(search.total ?? 0 >= search.results.count)
  #expect(search.results.contains { !$0.hits.isEmpty })

  let posts = try BlogFeedParser.parse(xml: try await client.blogFeed())
  #expect(posts.count > 200)
  let latest = try #require(posts.max { $0.number < $1.number })
  #expect(!(try BlogContentParser.blocks(html: latest.contentHTML)).isEmpty)

  let page = try EpisodePageParser.parse(html: try await client.episodePage("ep1-functions"), url: nil)
  #expect(page.transcript.chapters.count >= 5)
  #expect(!page.isTruncated)
  #expect(page.transcript.hasBody)
}

@Test(.enabled(if: live)) func liveCollections() async throws {
  let client = liveClient()
  let index = try CollectionsParser.parseIndex(html: try await client.collectionsPage())
  #expect(index.contains { $0.slug == "composable-architecture" })
  let c = try CollectionsParser.parseCollection(html: try await client.collectionPage("composable-architecture"), slug: "composable-architecture")
  #expect(c.sections.contains { $0.slug == "testing" })
  let s = try CollectionsParser.parseSection(html: try await client.sectionPage("composable-architecture", "testing"))
  #expect(s.groups.first?.episodes.contains { $0.number == 82 } == true)
}

@Test(.enabled(if: live)) func liveLockedEpisodeWithSavedSession() async throws {
  let client = liveClient()
  let page = try EpisodePageParser.parse(html: try await client.episodePage("381"), url: nil)
  let signedIn = (try? SessionStore.liveValue.load()) != nil
  #expect(page.isTruncated == !signedIn)
}
