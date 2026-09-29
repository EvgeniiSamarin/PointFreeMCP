import Foundation
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

@Test func collectionLinkWithoutSlugIsSkipped() throws {
  let html = #"<html><body><a href="/collections/"><h4>Broken</h4></a><a href="/collections/tca"><h4>TCA</h4></a></body></html>"#
  #expect(try CollectionsParser.parseIndex(html: html).map(\.slug) == ["tca"])
}

@Test func collectionWithoutSectionsIsStructureChange() throws {
  let url = try #require(URL(string: "https://www.pointfree.co/collections/tca"))
  #expect(throws: PointFreeError.structureChanged("collection sections", url)) {
    _ = try CollectionsParser.parseCollection(html: "<html><body><h1>TCA</h1></body></html>", slug: "tca")
  }
}

@Test func sectionWithoutEpisodesIsStructureChange() throws {
  let url = try #require(URL(string: "https://www.pointfree.co/collections/tca/testing"))
  #expect(throws: PointFreeError.structureChanged("section episodes", url)) {
    _ = try CollectionsParser.parseSection(html: "<html><body><h1>Testing</h1><h2>Core lessons</h2></body></html>", url: url)
  }
}
