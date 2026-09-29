import Foundation
import Testing
@testable import PointFreeKit

private func detail381() -> EpisodeDetail {
  EpisodeDetail(id: 381, sequence: 381, title: "Designing for Isolation: Naively", blurb: "Blurb 381", length: 1008,
                publishedAt: Date(timeIntervalSinceReferenceDate: 812246400), subscriberOnly: true, image: "",
                codeSampleDirectory: "0381-isolation-design-pt2",
                references: [Reference(title: "FCIS", link: "https://example.invalid/fcis", author: "Gary", blurb: nil, publishedAt: nil)])
}

private func transcript() -> Transcript {
  Transcript(chapters: [
    .init(slug: "introduction", title: "Introduction", startTimestamp: 5, blocks: [
      .speaker("Brandon"), .timestamp(5), .paragraph("Hello `x`."), .code("let a = 1\n"), .listItem("Item"),
    ]),
    .init(slug: "next-time", title: "Next time", startTimestamp: 902, blocks: [.timestamp(902), .paragraph("Bye."), .quote("Note."), .heading("Sub")]),
  ])
}

@Test func rendersFullEpisode() throws {
  let md = try MarkdownRenderer.episode(detail: detail381(), transcript: transcript(), section: nil)
  let expected = """
  # Episode #381: Designing for Isolation: Naively

  - Published: 2026-09-28
  - Duration: 16:48
  - Access: Members only
  - URL: https://www.pointfree.co/episodes/381
  - Code samples: https://github.com/pointfreeco/episode-code-samples/tree/main/0381-isolation-design-pt2

  > Blurb 381

  ## References

  - [FCIS](https://example.invalid/fcis) — Gary

  ## Introduction [0:05](https://www.pointfree.co/episodes/381#t5)

  **Brandon**

  Hello `x`.

  ```swift
  let a = 1
  ```

  - Item

  ## Next time [15:02](https://www.pointfree.co/episodes/381#t902)

  Bye.

  > Note.

  ### Sub


  """
  #expect(md == expected)
}

@Test func keepsTimestampsOtherThanTheChapterStart() throws {
  let t = Transcript(chapters: [
    .init(slug: "a", title: "A", startTimestamp: 5, blocks: [.timestamp(5), .paragraph("One."), .timestamp(68), .paragraph("Two.")]),
  ])
  let md = try MarkdownRenderer.episode(detail: detail381(), transcript: t, section: nil)
  #expect(md.hasSuffix("## A [0:05](https://www.pointfree.co/episodes/381#t5)\n\nOne.\n\n[1:08](https://www.pointfree.co/episodes/381#t68)\n\nTwo.\n\n"))
}

@Test func quotesEveryLineOfAMultiLineBlurb() throws {
  var detail = detail381()
  detail.blurb = "Line one.\n\nLine two."
  let md = try MarkdownRenderer.episode(detail: detail, transcript: Transcript(chapters: []), section: nil)
  #expect(md.contains("\n\n> Line one.\n>\n> Line two.\n\n## References"))
}

@Test func rendersOnlyRequestedSection() throws {
  let md = try MarkdownRenderer.episode(detail: detail381(), transcript: transcript(), section: .timestamp(902))
  #expect(md.contains("## Next time"))
  #expect(!md.contains("## Introduction"))
  #expect(md.contains("Showing section 2 of 2"))
}

@Test func unknownSectionListsAvailableChapters() {
  #expect(throws: PointFreeError.invalidArgument("Section \"nope\" not found. Available sections: introduction (0:05), next-time (15:02)")) {
    _ = try MarkdownRenderer.episode(detail: detail381(), transcript: transcript(), section: .slug("nope"))
  }
}

@Test func rendersSearchResults() {
  let results = [SearchResult(slug: "ep381-x", number: 381, title: "T", snippet: "… Sendable …",
                              hits: [.init(title: "Hit", timestamp: 349)])]
  let summary = EpisodeSummary(id: 381, sequence: 381, title: "T", blurb: "", length: 1008,
                               publishedAt: Date(timeIntervalSinceReferenceDate: 812246400), subscriberOnly: true, image: "")
  let md = MarkdownRenderer.search(query: SearchQuery(query: "Sendable", scope: .dialogue), page: SearchPage(total: 80, results: results), episodes: [381: summary])
  #expect(md.hasPrefix("# Search: Sendable (scope: dialogue)\n\nShowing 1 of 80 matching video(s). The site returns at most ~50; narrow with `scope` or `access` to see the rest.\n\n"))
  #expect(md.contains("## #381: T (Members only)\n"))
  #expect(md.contains("https://www.pointfree.co/episodes/ep381-x\n"))
  #expect(md.contains("> … Sendable …"))
  #expect(md.contains("- [Hit (5:49)](https://www.pointfree.co/episodes/ep381-x#t349)"))
}

@Test func rendersEmptySearch() {
  let md = MarkdownRenderer.search(query: SearchQuery(query: "zzz"), page: SearchPage(total: nil, results: []), episodes: [:])
  #expect(md.contains("No episodes matched"))
}

@Test func rendersCompleteSearchWithoutWarning() {
  let r = [SearchResult(slug: "ep1-x", number: 1, title: "T", snippet: nil, hits: [])]
  let md = MarkdownRenderer.search(query: SearchQuery(query: "q"), page: SearchPage(total: 1, results: r), episodes: [:])
  #expect(md.contains("1 matching video(s).\n"))
  #expect(!md.contains("narrow with"))
}

@Test func rendersBlogPostAndList() throws {
  let postURL = try #require(URL(string: "https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone"))
  let post = BlogPost(number: 228, slug: "228-lazystate-1-0-now-available-to-everyone", title: "LazyState 1.0",
                      url: postURL,
                      updated: Date(timeIntervalSince1970: 1_789_300_000), contentHTML: "")
  let md = MarkdownRenderer.blogPost(post, blocks: [.paragraph("Hi"), .code("let x = 1\n"), .heading("Why")])
  #expect(md.hasPrefix("# LazyState 1.0\n\n- Published: 2026-09-13\n- URL: https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone\n\nHi\n\n```swift\nlet x = 1\n```\n\n### Why\n"))
  let list = MarkdownRenderer.blogList([post])
  #expect(list.contains("- #228 LazyState 1.0 — 2026-09-13 · https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone"))
}

@Test func rendersEpisodeListAndCollections() {
  let e = EpisodeSummary(id: 1, sequence: 1, title: "Functions", blurb: "", length: 1219,
                         publishedAt: Date(timeIntervalSinceReferenceDate: 538899069), subscriberOnly: false, image: "")
  #expect(MarkdownRenderer.episodeList([e]).contains("- #1 Functions — 2018-01-29 · 20:19 · Free · https://www.pointfree.co/episodes/1"))
  let c = MarkdownRenderer.collections([.init(slug: "tca", title: "TCA", description: "Desc")])
  #expect(c.contains("- **TCA** (`tca`): Desc"))
  let s = MarkdownRenderer.section(collectionSlug: "tca", sectionSlug: "testing", title: "Testing",
                                   groups: [.init(heading: "Core lessons", episodes: [.init(number: 82, slug: "ep82-x", title: "X", duration: "35 min")])])
  #expect(s.contains("## Core lessons\n\n- #82 X (35 min) — https://www.pointfree.co/episodes/ep82-x"))
}
