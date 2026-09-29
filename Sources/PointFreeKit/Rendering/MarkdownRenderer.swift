import Foundation

public enum MarkdownRenderer {
  static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  static func date(_ d: Date) -> String { dateFormatter.string(from: d) }
  static func episodeURL(_ slugOrID: String) -> String { "https://www.pointfree.co/episodes/\(slugOrID)" }
  static func tsLink(_ base: String, _ seconds: Int) -> String { "[\(Timecode.label(seconds: seconds))](\(base)#t\(seconds))" }

  public static func episode(detail: EpisodeDetail, transcript: Transcript, section: SectionRef?) throws(PointFreeError) -> String {
    let base = detail.pageURL.absoluteString
    var out = "# Episode #\(detail.sequence): \(detail.title)\n\n"
    out += "- Published: \(date(detail.publishedAt))\n"
    out += "- Duration: \(detail.durationLabel)\n"
    out += "- Access: \(detail.accessLabel)\n"
    out += "- URL: \(base)\n"
    if let code = detail.codeSampleURL { out += "- Code samples: \(code.absoluteString)\n" }
    out += "\n> \(detail.blurb)\n\n"
    if !detail.references.isEmpty {
      out += "## References\n\n"
      for r in detail.references {
        let name = r.link.map { "[\(r.title)](\($0))" } ?? r.title
        out += "- \(name)" + (r.author.map { " — \($0)" } ?? "") + "\n"
      }
      out += "\n"
    }

    var chapters = transcript.chapters
    if let section {
      guard let index = chapters.firstIndex(where: { $0 == transcript.chapter(matching: section) }) else {
        let available = chapters.map { "\($0.slug) (\($0.startTimestamp.map { Timecode.label(seconds: $0) } ?? "-"))" }.joined(separator: ", ")
        throw .invalidArgument("Section \"\(sectionText(section))\" not found. Available sections: \(available)")
      }
      out += "_Showing section \(index + 1) of \(chapters.count). Omit `section` for the full transcript._\n\n"
      chapters = [chapters[index]]
    }

    for chapter in chapters {
      out += "## \(chapter.title)"
      if let ts = chapter.startTimestamp { out += " " + tsLink(base, ts) }
      out += "\n\n"
      out += blocks(chapter.blocks, base: base)
    }
    return out
  }

  /// Общий рендер блоков без глав (блог).
  static func blocks(_ blocks: [Transcript.Block], base: String) -> String {
    var out = ""
    for block in blocks {
      switch block {
      case .timestamp(let s): out += tsLink(base, s) + "\n\n"
      case .speaker(let name): out += "**\(name)**\n\n"
      case .paragraph(let text): out += text + "\n\n"
      case .code(let code): out += "```swift\n\(code.hasSuffix("\n") ? code : code + "\n")```\n\n"
      case .listItem(let text): out += "- \(text)\n"
      case .quote(let text): out += "> \(text)\n\n"
      case .heading(let text): out += "### \(text)\n\n"
      }
    }
    if case .listItem = blocks.last { out += "\n" }
    return out
  }

  public static func blogPost(_ post: BlogPost, blocks: [Transcript.Block]) -> String {
    var out = "# \(post.title)\n\n- Published: \(date(post.updated))\n- URL: \(post.url.absoluteString)\n\n"
    out += Self.blocks(blocks, base: post.url.absoluteString)
    return out
  }

  public static func blogList(_ posts: [BlogPost]) -> String {
    var out = "# Point-Free Pointers blog (\(posts.count))\n\nCall `fetchBlogPost` with a post number, slug or URL to read one.\n\n"
    for p in posts { out += "- #\(p.number) \(p.title) — \(date(p.updated)) · \(p.url.absoluteString)\n" }
    return out
  }

  static func sectionText(_ ref: SectionRef) -> String {
    switch ref { case .slug(let s): return s; case .timestamp(let t): return "t\(t)" }
  }

  public static func search(query: SearchQuery, page: SearchPage, episodes: [Int: EpisodeSummary]) -> String {
    let results = page.results
    var out = "# Search: \(query.query)"
    if let scope = query.scope { out += " (scope: \(scope.rawValue))" }
    out += "\n\n"
    guard !results.isEmpty else {
      return out + "No episodes matched. Try a broader query, another `scope` (dialogue, code, titles), or drop `access`.\n"
    }
    if let total = page.total, total > results.count {
      out += "Showing \(results.count) of \(total) matching video(s). The site returns at most ~50; narrow with `scope` or `access` to see the rest.\n\n"
    } else {
      out += "\(results.count) matching video(s).\n\n"
    }
    for r in results {
      let summary = r.number.flatMap { episodes[$0] }
      let number = r.number.map { "#\($0): " } ?? ""
      let access = summary.map { " (\($0.accessLabel))" } ?? ""
      out += "## \(number)\(r.title)\(access)\n\(episodeURL(r.slug))\n\n"
      if let snippet = r.snippet { out += "> \(snippet)\n\n" }
      for hit in r.hits {
        out += "- [\(hit.title) (\(Timecode.label(seconds: hit.timestamp)))](\(episodeURL(r.slug))#t\(hit.timestamp))\n"
      }
      if !r.hits.isEmpty { out += "\n" }
    }
    return out
  }

  public static func episodeList(_ episodes: [EpisodeSummary]) -> String {
    var out = "# Point-Free episodes (\(episodes.count))\n\n"
    for e in episodes {
      out += "- #\(e.sequence) \(e.title) — \(date(e.publishedAt)) · \(e.durationLabel) · \(e.accessLabel) · \(episodeURL(String(e.id)))\n"
    }
    return out
  }

  public static func collections(_ list: [CollectionSummary]) -> String {
    var out = "# Point-Free collections (\(list.count))\n\nCall `fetchCollection` with `slug` to list its sections.\n\n"
    for c in list { out += "- **\(c.title)** (`\(c.slug)`)" + (c.description.map { ": \($0)" } ?? "") + "\n" }
    return out
  }

  public static func collection(title: String, slug: String, sections: [CollectionSection]) -> String {
    var out = "# Collection: \(title)\n\nhttps://www.pointfree.co/collections/\(slug)\n\nCall `fetchCollection` with `slug` and `section` to list episodes.\n\n"
    for s in sections { out += "- **\(s.title)** (`\(s.slug)`)\n" }
    return out
  }

  public static func section(collectionSlug: String, sectionSlug: String, title: String, groups: [SectionGroup]) -> String {
    var out = "# \(title)\n\nhttps://www.pointfree.co/collections/\(collectionSlug)/\(sectionSlug)\n\n"
    for g in groups {
      out += "## \(g.heading)\n\n"
      for e in g.episodes {
        out += "- #\(e.number) \(e.title)" + (e.duration.map { " (\($0))" } ?? "") + " — \(episodeURL(e.slug))\n"
      }
      out += "\n"
    }
    return out
  }
}
