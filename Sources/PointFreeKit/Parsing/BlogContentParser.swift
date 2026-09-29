import Foundation
import SwiftSoup

public enum BlogContentParser {
  public static func blocks(html: String) throws -> [Transcript.Block] {
    let doc = try SwiftSoup.parseBodyFragment(html)
    var blocks: [Transcript.Block] = []
    for node in try doc.body()!.select("h1, h2, h3, h4, h5, h6, p, pre, li, blockquote") {
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
