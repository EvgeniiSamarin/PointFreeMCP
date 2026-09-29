import Foundation
import Testing
@testable import PointFreeKit

@Test func parsesFreeEpisodeTranscript() throws {
  let page = try EpisodePageParser.parse(html: fixtureString("episode-free.html"), url: nil)
  #expect(page.tocChapterCount == 2)
  #expect(!page.isTruncated)
  let t = page.transcript
  #expect(t.chapters.map(\.title) == ["Introduction", "Composition"])
  #expect(t.chapters.map(\.slug) == ["introduction", "composition"])
  #expect(t.chapters[0].startTimestamp == 5)
  #expect(t.chapters[1].startTimestamp == 141)

  let intro = t.chapters[0].blocks
  #expect(intro[0] == .speaker("Brandon"))
  #expect(intro[1] == .timestamp(5))
  #expect(intro[2] == .paragraph("Placeholder intro with `incr` and a [link](https://www.pointfree.co/episodes/ep2-side-effects), plus *emphasis* and **bold**."))
  #expect(intro[3] == .code("func incr(_ x: Int) -> Int {\n  return x + 1  // a & b < c\n}\n"))
  #expect(intro[4] == .timestamp(68))
  #expect(intro[5] == .paragraph("Second paragraph."))
  #expect(intro[6] == .listItem("First item with `code`"))
  #expect(intro[7] == .listItem("Second item"))
  #expect(intro.count == 8)

  let comp = t.chapters[1].blocks
  #expect(comp.contains(.code("let f = incr >>> square")))
  #expect(comp.contains(.quote("Quoted `note`.")))
  #expect(comp.contains(.heading("Inner heading")))
  #expect(comp.contains(.paragraph("After heading.")))
  #expect(!comp.contains(.paragraph("Quoted `note`.")))
  #expect(t.chapters.count == 2)  // h3 внутри статьи не открывает новую главу
  #expect(t.hasBody)
  // Текст футера не попал в транскрипт
  #expect(!t.chapters.flatMap(\.blocks).contains(.paragraph("Footer text must not appear.")))
}

@Test func detectsTruncatedLockedEpisode() throws {
  let page = try EpisodePageParser.parse(html: fixtureString("episode-locked.html"), url: nil)
  #expect(page.tocChapterCount == 4)
  #expect(page.transcript.chapters.count == 2)
  #expect(page.isTruncated)
}

@Test func missingArticleIsStructureChange() {
  #expect(throws: PointFreeError.structureChanged("article", nil)) {
    _ = try EpisodePageParser.parse(html: "<html><body><p>nope</p></body></html>", url: nil)
  }
}
