import Foundation
import SwiftSoup

public enum SearchPageParser {
  public static func parse(html: String, url: URL?) throws -> SearchPage {
    let doc = try SwiftSoup.parse(html)
    let bodyText = try doc.body()?.text() ?? ""
    let total = bodyText.firstMatch(of: /(\d+) videos? match/).flatMap { Int($0.1) }
    var results: [SearchResult] = []
    for titleLink in try doc.select("h4 > a[href^=/episodes/]") {
      let href = try titleLink.attr("href")
      let slug = String(href.dropFirst("/episodes/".count)).split(separator: "#")[0].description
      let title = try titleLink.text()
      let card = try cardContainer(for: titleLink) ?? titleLink
      let snippet = try card.select("p:has(mark)").first().map { try $0.text() }
      var hits: [SearchResult.Hit] = []
      for link in try card.select("a[href*=#t]") {
        let hitHref = try link.attr("href")
        guard let fragment = hitHref.split(separator: "#").last, let seconds = Int(fragment.dropFirst()) else { continue }
        let text = try link.text()
        hits.append(.init(title: stripTimeSuffix(text), timestamp: seconds))
      }
      results.append(SearchResult(slug: slug, number: EpisodeRef.parse(slug)?.number, title: title, snippet: snippet, hits: hits))
    }
    if results.isEmpty, let total, total > 0 {
      throw PointFreeError.structureChanged("search result cards", url)
    }
    return SearchPage(total: total, results: results)
  }

  /// Ближайший предок, в котором ровно одна ссылка на эпизод без "#".
  static func cardContainer(for link: Element) throws -> Element? {
    var best: Element? = nil
    var current = link.parent()
    while let node = current {
      let episodeLinks = try node.select("a[href^=/episodes/]").filter { !(try $0.attr("href")).contains("#") }
      if episodeLinks.count > 1 { break }
      best = node
      current = node.parent()
    }
    return best
  }

  /// "Title (5:49)" -> "Title"
  static func stripTimeSuffix(_ text: String) -> String {
    guard let open = text.lastIndex(of: "("), text.hasSuffix(")") else { return text }
    return String(text[..<open]).trimmingCharacters(in: .whitespaces)
  }
}
