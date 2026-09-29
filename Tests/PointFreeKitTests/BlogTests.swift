import Foundation
import Testing
@testable import PointFreeKit

@Test func parsesAtomFeedEntries() throws {
  let posts = try BlogFeedParser.parse(xml: fixtureString("blog-atom.xml"))
  #expect(posts.count == 2)
  let post = try #require(posts.first { $0.number == 228 })
  #expect(post.slug == "228-lazystate-1-0-now-available-to-everyone")
  #expect(post.title == "LazyState 1.0: Now available to everyone")
  #expect(post.url.absoluteString == "https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone")
  #expect(post.updated == Date(timeIntervalSince1970: 1_789_344_000))
  #expect(post.contentHTML.contains("<pre><code>@LazyState"))
}

@Test func convertsPostContentToBlocks() throws {
  let post = try #require(try BlogFeedParser.parse(xml: fixtureString("blog-atom.xml")).first { $0.number == 228 })
  let blocks = try BlogContentParser.blocks(html: post.contentHTML)
  #expect(blocks == [
    .paragraph("We are excited to announce [LazyState](https://github.com/pointfreeco/swiftui-lazy-state) **1.0**."),
    .heading("Usage"),
    .code("@LazyState var model = Model()\n"),
    .listItem("One"),
    .listItem("Two with `code`"),
    .quote("Quoted."),
  ])
}

@Test(arguments: [
  ("228", 228), ("228-lazystate-1-0-now-available-to-everyone", 228),
  ("https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone", 228), ("/blog/posts/1-announcing", 1),
])
func parsesBlogPostRefs(raw: String, number: Int) throws {
  #expect(try #require(BlogPostRef.parse(raw)).number == number)
}

@Test(arguments: ["", "lazystate", "https://www.pointfree.co/episodes/ep1-functions"])
func rejectsBadBlogRefs(raw: String) {
  #expect(BlogPostRef.parse(raw) == nil)
}

@Test func malformedFeedIsStructureChange() {
  #expect(throws: PointFreeError.self) {
    _ = try BlogFeedParser.parse(xml: "<html>not a feed</html>")
  }
}

@Test func parsesBlogPostPageArticle() throws {
  let blocks = try BlogContentParser.blocks(page: fixtureString("blog-post.html"), url: nil)
  #expect(blocks == [
    .paragraph("We are excited to announce [LazyState](https://github.com/pointfreeco/swiftui-lazy-state) **1.0**."),
    .heading("Usage"),
    .code("@LazyState var model = Model()\n"),
    .listItem("One"),
    .listItem("Two with `code`"),
    .quote("Quoted."),
  ])
}

@Test func blogPageWithoutArticleIsStructureChange() {
  #expect(throws: PointFreeError.structureChanged("article", nil)) {
    _ = try BlogContentParser.blocks(page: "<html><body><p>nope</p></body></html>", url: nil)
  }
}
