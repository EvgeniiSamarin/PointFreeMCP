import Testing
@testable import PointFreeKit

@Test func parsesCollectionsIndex() throws {
  let list = try CollectionsParser.parseIndex(html: fixtureString("collections.html"))
  #expect(list == [
    .init(slug: "composable-architecture", title: "Composable Architecture", description: "TCA description."),
    .init(slug: "concurrency", title: "Concurrency", description: "Concurrency description."),
  ])
}

@Test func emptyCollectionsIndexIsStructureChange() {
  #expect(throws: PointFreeError.self) {
    _ = try CollectionsParser.parseIndex(html: "<html><body><p>nothing</p></body></html>")
  }
}

@Test func parsesCollectionSections() throws {
  let c = try CollectionsParser.parseCollection(html: fixtureString("collection.html"), slug: "composable-architecture")
  #expect(c.title == "Composable Architecture")
  #expect(c.sections == [
    .init(slug: "swiftui-and-state-management", title: "SwiftUI and State Management"),
    .init(slug: "testing", title: "Testing"),
  ])
}

@Test func parsesSectionEpisodesGroupedByHeading() throws {
  let s = try CollectionsParser.parseSection(html: fixtureString("section.html"))
  #expect(s.title == "Testing")
  #expect(s.groups.map(\.heading) == ["Core lessons", "Related content"])
  #expect(s.groups[0].episodes == [
    .init(number: 82, slug: "ep82-testable-state-management-reducers", title: "Testable State Management: Reducers", duration: "35 min"),
    .init(number: 83, slug: "ep83-testable-state-management-effects", title: "Testable State Management: Effects", duration: "41 min"),
  ])
  #expect(s.groups[1].episodes == [
    .init(number: 86, slug: "ep86-swiftui-snapshot-testing", title: "SwiftUI Snapshot Testing", duration: "28 min"),
  ])
}
