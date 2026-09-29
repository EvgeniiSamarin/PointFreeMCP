import Foundation

public enum PointFreeJSON {
  /// Сайт кодирует даты стратегией по умолчанию JSONEncoder: секунды от 2001-01-01.
  public static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .deferredToDate
    return decoder
  }()
}

public struct EpisodeSummary: Codable, Equatable, Sendable, Identifiable {
  public var id: Int
  public var sequence: Int
  public var title: String
  public var blurb: String
  public var length: Int
  public var publishedAt: Date
  public var subscriberOnly: Bool
  public var image: String

  public init(id: Int, sequence: Int, title: String, blurb: String, length: Int, publishedAt: Date, subscriberOnly: Bool, image: String) {
    self.id = id; self.sequence = sequence; self.title = title; self.blurb = blurb
    self.length = length; self.publishedAt = publishedAt; self.subscriberOnly = subscriberOnly; self.image = image
  }

  public var durationLabel: String { Timecode.label(seconds: length) }
  public var accessLabel: String { subscriberOnly ? "Members only" : "Free" }
}

public struct Reference: Codable, Equatable, Sendable {
  public var title: String
  public var link: String?
  public var author: String?
  public var blurb: String?
  public var publishedAt: Date?
}

public struct EpisodeDetail: Codable, Equatable, Sendable, Identifiable {
  public var id: Int
  public var sequence: Int
  public var title: String
  public var blurb: String
  public var length: Int
  public var publishedAt: Date
  public var subscriberOnly: Bool
  public var image: String
  public var codeSampleDirectory: String?
  public var references: [Reference]

  public var durationLabel: String { Timecode.label(seconds: length) }
  public var accessLabel: String { subscriberOnly ? "Members only" : "Free" }
  public var pageURL: URL {
    guard let url = URL(string: "https://www.pointfree.co/episodes/\(id)") else { preconditionFailure("invalid episode URL") }
    return url
  }
  public var codeSampleURL: URL? {
    codeSampleDirectory.flatMap {
      URL(string: "https://github.com/pointfreeco/episode-code-samples/tree/main/\($0)")
    }
  }
}

public enum Timecode {
  /// 68 -> "1:08", 3723 -> "1:02:03"
  public static func label(seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0
      ? String(format: "%d:%02d:%02d", h, m, s)
      : String(format: "%d:%02d", m, s)
  }

  /// "1:08" -> 68, "1:02:03" -> 3723, "t349" -> 349, "349" -> 349; иначе nil
  public static func seconds(from text: String) -> Int? {
    var raw = text.trimmingCharacters(in: .whitespaces)
    if raw.hasPrefix("t") { raw.removeFirst() }
    if let n = Int(raw) { return n }
    let parts = raw.split(separator: ":").map { Int($0) }
    guard parts.count >= 2, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
    let nums = parts.compactMap { $0 }
    return nums.reduce(0) { $0 * 60 + $1 }
  }
}
