import Foundation

public struct BlogPost: Equatable, Sendable {
  public var number: Int
  public var slug: String
  public var title: String
  public var url: URL
  public var updated: Date
  public var contentHTML: String

  public init(number: Int, slug: String, title: String, url: URL, updated: Date, contentHTML: String) {
    self.number = number; self.slug = slug; self.title = title; self.url = url; self.updated = updated; self.contentHTML = contentHTML
  }
}

public struct BlogPostRef: Equatable, Sendable {
  public var number: Int

  /// "228", "228-slug", "https://www.pointfree.co/blog/posts/228-slug", "/blog/posts/228-slug"
  public static func parse(_ raw: String) -> BlogPostRef? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let q = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<q]) }
    if text.contains("/") {
      guard let range = text.range(of: "/blog/posts/") else { return nil }
      text = String(text[range.upperBound...])
    }
    while text.hasSuffix("/") { text.removeLast() }
    guard let match = text.wholeMatch(of: /(\d+)(?:-[A-Za-z0-9-]*)?/), let number = Int(match.1) else { return nil }
    return BlogPostRef(number: number)
  }
}
