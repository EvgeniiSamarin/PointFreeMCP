public struct Transcript: Equatable, Sendable {
  public struct Chapter: Equatable, Sendable {
    public var slug: String
    public var title: String
    public var startTimestamp: Int?
    public var blocks: [Block]
    public init(slug: String, title: String, startTimestamp: Int? = nil, blocks: [Block] = []) {
      self.slug = slug; self.title = title; self.startTimestamp = startTimestamp; self.blocks = blocks
    }
  }

  public enum Block: Equatable, Sendable {
    case timestamp(Int)
    case speaker(String)
    case paragraph(String)
    case code(String)
    case listItem(String)
    case quote(String)
    case heading(String)
  }

  public var chapters: [Chapter]
  public init(chapters: [Chapter]) { self.chapters = chapters }

  /// Есть ли содержательный текст (абзацы или код), а не только оглавление.
  public var hasBody: Bool {
    chapters.contains { chapter in
      chapter.blocks.contains { block in
        if case .paragraph = block { return true }
        if case .code = block { return true }
        return false
      }
    }
  }

  public func chapter(matching ref: SectionRef) -> Chapter? {
    switch ref {
    case .slug(let slug):
      if let exact = chapters.first(where: { $0.slug == slug }) { return exact }
      return chapters.first { $0.title.lowercased().contains(slug.replacingOccurrences(of: "-", with: " ")) }
    case .timestamp(let seconds):
      if let containing = chapters.first(where: { $0.blocks.contains(.timestamp(seconds)) }) { return containing }
      return chapters.last { ($0.startTimestamp ?? Int.max) <= seconds }
    }
  }
}
