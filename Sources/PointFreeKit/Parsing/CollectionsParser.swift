import Foundation
import SwiftSoup

public enum CollectionsParser {
  public static func parseIndex(html: String) throws -> [CollectionSummary] {
    let doc = try SwiftSoup.parse(html)
    var result: [CollectionSummary] = []
    for link in try doc.select("a[href^=/collections/]:has(h4)") {
      let slug = String(try link.attr("href").dropFirst("/collections/".count)).split(separator: "/")[0].description
      let title = try link.select("h4").first()?.text() ?? ""
      let description = try link.nextElementSibling()?.select("p").first()?.text()
      result.append(.init(slug: slug, title: title, description: description?.isEmpty == false ? description : nil))
    }
    guard !result.isEmpty else {
      throw PointFreeError.structureChanged("collections index", URL(string: "https://www.pointfree.co/collections"))
    }
    return result
  }

  public static func parseCollection(html: String, slug: String) throws -> (title: String, sections: [CollectionSection]) {
    let doc = try SwiftSoup.parse(html)
    let title = try doc.select("h1").first()?.text() ?? slug
    var sections: [CollectionSection] = []
    for link in try doc.select("a[href*=/collections/\(slug)/]") {
      let href = try link.attr("href")
      guard let sectionSlug = href.split(separator: "/").last.map(String.init), !sectionSlug.isEmpty else { continue }
      let sectionTitle = try link.select("div > div").first()?.text() ?? (try link.text())
      sections.append(.init(slug: sectionSlug, title: sectionTitle))
    }
    return (title, sections)
  }

  public static func parseSection(html: String) throws -> (title: String, groups: [SectionGroup]) {
    let doc = try SwiftSoup.parse(html)
    let title = try doc.select("h1").first()?.text() ?? ""
    var groups: [SectionGroup] = []
    let episodePattern = /(?:\/episodes\/|\/collections\/[^\/]+\/[^\/]+\/)(ep(\d+)-[a-z0-9-]+)/
    for node in try doc.select("h2, a[href*=/ep]") {
      if node.tagName() == "h2" {
        groups.append(.init(heading: try node.text(), episodes: []))
        continue
      }
      guard let match = try node.attr("href").firstMatch(of: episodePattern), let number = Int(match.2) else { continue }
      let divs = try node.select("div")
      let episodeTitle = try divs.first().map { (try? $0.text()) ?? "" } ?? node.text()
      let duration: String? = try (divs.count > 1 ? divs.get(1).text().replacingOccurrences(of: "\u{00A0}", with: " ") : nil)
      let episode = SectionEpisode(number: number, slug: String(match.1), title: episodeTitle, duration: duration)
      if groups.isEmpty { groups.append(.init(heading: "Episodes", episodes: [])) }
      groups[groups.count - 1].episodes.append(episode)
    }
    return (title, groups.filter { !$0.episodes.isEmpty })
  }
}
