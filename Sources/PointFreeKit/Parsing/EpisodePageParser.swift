import Foundation
import SwiftSoup

public struct EpisodePage: Equatable, Sendable {
  public var transcript: Transcript
  public var tocChapterCount: Int
  public var isTruncated: Bool { tocChapterCount > transcript.chapters.count }
}

public enum EpisodePageParser {
  public static func parse(html: String, url: URL?) throws -> EpisodePage {
    let doc = try SwiftSoup.parse(html)
    guard let article = try doc.select("article").first() else {
      throw PointFreeError.structureChanged("article", url)
    }

    // TOC: ссылки на главы вне article (href="#slug" без data-timestamp)
    let tocLinks = try doc.select("li > a[href^=#]:not([data-timestamp])")
      .filter { link in !(link.parents().contains { $0.tagName() == "article" }) }
    let tocChapterCount = Set(try tocLinks.map { try $0.attr("href") }).count

    var chapters: [Transcript.Chapter] = []
    var pendingSlug: String?

    func append(_ block: Transcript.Block) {
      // Тело транскрипта начинается с первого заголовка главы; блоки до него не учитываются.
      guard !chapters.isEmpty else { return }
      chapters[chapters.count - 1].blocks.append(block)
      if case .timestamp(let s) = block, chapters[chapters.count - 1].startTimestamp == nil {
        chapters[chapters.count - 1].startTimestamp = s
      }
    }

    func isInside(_ element: Element, _ tags: Set<String>) -> Bool {
      var current = element.parent()
      while let node = current, node.tagName() != "article" {
        if tags.contains(node.tagName()) { return true }
        current = node.parent()
      }
      return false
    }

    for node in try article.select("a[id], h4, h2, h3, h5, h6, a[data-timestamp], strong, p, pre, li, blockquote") {
      switch node.tagName() {
      case "a" where node.hasAttr("data-timestamp"):
        if let seconds = Int(try node.attr("data-timestamp")) { append(.timestamp(seconds)) }
      case "a":
        let id = try node.attr("id")
        if !id.isEmpty { pendingSlug = id }
      case "h4":
        let title = node.ownText().trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { continue }
        chapters.append(.init(slug: pendingSlug ?? slugify(title), title: title))
        pendingSlug = nil
      case "h2", "h3", "h5", "h6":
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { append(.heading(text)) }
      case "blockquote":
        let text = try node.select("p").map { try InlineMarkdown.render($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        let quote = try (text.isEmpty ? InlineMarkdown.render(node) : text)
        append(.quote(quote))
      case "strong":
        guard !isInside(node, ["p", "li", "h4", "blockquote"]) else { continue }
        let name = try node.text().trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { append(.speaker(name)) }
      case "p":
        guard !isInside(node, ["li", "blockquote"]) else { continue }
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { append(.paragraph(text)) }
      case "pre":
        let code = try node.select("code").first() ?? node
        var text = InlineMarkdown.rawText(code)
        if !text.hasSuffix("\n") && text.contains("\n") { text += "\n" }
        append(.code(text))
      case "li":
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { append(.listItem(text)) }
      default: break
      }
    }

    return EpisodePage(transcript: Transcript(chapters: chapters), tocChapterCount: tocChapterCount)
  }

  static func slugify(_ title: String) -> String {
    title.lowercased()
      .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
      .joined()
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
  }
}
