import Testing
@testable import PointFreeKit

@Test func parsesSearchCards() throws {
  let page = try SearchPageParser.parse(html: fixtureString("search.html"), url: nil)
  #expect(page.total == 80)
  let results = page.results
  #expect(results.count == 2)
  #expect(results[0].slug == "ep381-designing-for-isolation-naively")
  #expect(results[0].number == 381)
  #expect(results[0].title == "Designing for Isolation: Naively")
  #expect(results[0].snippet == "… Sendable. Snippet text …")
  #expect(results[0].hits == [
    .init(title: "Remaining non-Sendable a bit longer…", timestamp: 349),
    .init(title: "Next time: Nonisolated Core", timestamp: 902),
  ])
  #expect(results[1].title == "Concurrency's Future: Sendable and Actors")
  #expect(results[1].snippet == nil)
  #expect(results[1].hits == [.init(title: "Sendable", timestamp: 688)])
}

@Test func emptySearchGivesNoResults() throws {
  let page = try SearchPageParser.parse(html: "<html><body><h1>Search</h1><p>No results</p></body></html>", url: nil)
  #expect(page.results.isEmpty)
  #expect(page.total == nil)
}

@Test func matchesWithoutCardsIsStructureChange() {
  #expect(throws: PointFreeError.structureChanged("search result cards", nil)) {
    _ = try SearchPageParser.parse(html: "<html><body><p>12 videos match x</p><div>new markup</div></body></html>", url: nil)
  }
}

@Test func cardWithEmptyEpisodeSlugIsSkipped() throws {
  let html = ##"<html><body><p>2 videos match</p><div><h4><a href="/episodes/#t5">Broken</a></h4></div><div><h4><a href="/episodes/ep1-functions">Functions</a></h4></div></body></html>"##
  let page = try SearchPageParser.parse(html: html, url: nil)
  #expect(page.results.map(\.slug) == ["ep1-functions"])
}
