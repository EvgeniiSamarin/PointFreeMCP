import Foundation

public enum SectionRef: Equatable, Sendable {
  case timestamp(Int)
  case slug(String)

  public static func parse(_ raw: String) -> SectionRef? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("#") { text.removeFirst() }
    guard !text.isEmpty else { return nil }
    let looksLikeTime = text.hasPrefix("t") && Int(text.dropFirst()) != nil || text.contains(":") || Int(text) != nil
    if looksLikeTime, let seconds = Timecode.seconds(from: text) { return .timestamp(seconds) }
    return .slug(text.lowercased())
  }
}

public struct EpisodeRef: Equatable, Sendable {
  public var number: Int
  public var slug: String?
  public var section: SectionRef?

  public var pathComponent: String { slug ?? String(number) }

  public static func parse(_ raw: String) -> EpisodeRef? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    var section: SectionRef? = nil
    if let hash = text.firstIndex(of: "#") {
      section = SectionRef.parse(String(text[text.index(after: hash)...]))
      text = String(text[..<hash])
    }
    if let q = text.firstIndex(of: "?") { text = String(text[..<q]) }
    if let range = text.range(of: "/episodes/") { text = String(text[range.upperBound...]) }
    while text.hasSuffix("/") { text.removeLast() }
    text = text.lowercased()
    if let number = Int(text) { return EpisodeRef(number: number, slug: nil, section: section) }
    let pattern = /^ep(\d+)(?:-[a-z0-9-]*)?$/
    guard let match = text.wholeMatch(of: pattern), let number = Int(match.1) else { return nil }
    return EpisodeRef(number: number, slug: text, section: section)
  }
}
