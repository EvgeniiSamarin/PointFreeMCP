import Foundation
import SwiftSoup

public enum InlineMarkdown {
  /// Переводит inline-разметку элемента (code, a, em, strong, br) в markdown; остальные теги — их текст.
  public static func render(_ element: Element, baseURL: URL = PointFreeClient.baseURL) throws -> String {
    var out = ""
    for node in element.getChildNodes() {
      if let text = node as? TextNode {
        out += text.getWholeText()
      } else if let child = node as? Element {
        switch child.tagName() {
        case "code": out += "`" + (try child.text()) + "`"
        case "em", "i": out += "*" + (try render(child, baseURL: baseURL)) + "*"
        case "strong", "b": out += "**" + (try render(child, baseURL: baseURL)) + "**"
        case "br": out += "\n"
        case "a":
          let href = try child.attr("href")
          let label = try render(child, baseURL: baseURL)
          let absolute = URL(string: href, relativeTo: baseURL)?.absoluteString ?? href
          out += href.isEmpty ? label : "[\(label)](\(absolute))"
        case "svg", "img": break
        default: out += try render(child, baseURL: baseURL)
        }
      }
    }
    return out.replacingOccurrences(of: "\u{00A0}", with: " ")
      .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: " ")
      .replacingOccurrences(of: "  ", with: " ")
      .trimmingCharacters(in: .whitespaces)
  }

  /// Исходный текст без нормализации пробелов (для <pre>).
  public static func rawText(_ element: Element) -> String {
    var out = ""
    for node in element.getChildNodes() {
      if let text = node as? TextNode { out += text.getWholeText() }
      else if let child = node as? Element { out += rawText(child) }
    }
    return out
  }
}
