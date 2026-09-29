import Foundation
import SwiftSoup

public enum BlogContentParser {
  /// HTML-фрагмент (например, из Atom-фида).
  public static func blocks(html: String) throws -> [Transcript.Block] {
    let doc = try SwiftSoup.parseBodyFragment(html)
    guard let body = doc.body() else { return [] }
    return try blocks(in: body)
  }

  /// Полная страница поста: тело — `article`.
  public static func blocks(page html: String, url: URL?) throws -> [Transcript.Block] {
    let doc = try SwiftSoup.parse(html)
    guard let article = try doc.select("article").first() else {
      throw PointFreeError.structureChanged("article", url)
    }
    return try blocks(in: article)
  }

  public static func blocks(in root: Element) throws -> [Transcript.Block] {
    var blocks: [Transcript.Block] = []
    for node in try root.select("h1, h2, h3, h4, h5, h6, p, pre, li, blockquote") {
      let insideQuoteOrItem = node.parents().contains { ["li", "blockquote"].contains($0.tagName()) }
      switch node.tagName() {
      case "h1", "h2", "h3", "h4", "h5", "h6":
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { blocks.append(.heading(text)) }
      case "p":
        guard !insideQuoteOrItem else { continue }
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { blocks.append(.paragraph(text)) }
      case "pre":
        let code = try node.select("code").first() ?? node
        var text = InlineMarkdown.rawText(code)
        if !text.hasSuffix("\n") && text.contains("\n") { text += "\n" }
        blocks.append(.code(text))
      case "li":
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { blocks.append(.listItem(text)) }
      case "blockquote":
        let text = try node.select("p").map { try InlineMarkdown.render($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        let quote = try (text.isEmpty ? InlineMarkdown.render(node) : text)
        blocks.append(.quote(quote))
      default: break
      }
    }
    return blocks
  }
}
