public struct SearchResult: Equatable, Sendable {
  public struct Hit: Equatable, Sendable {
    public var title: String
    public var timestamp: Int
    public init(title: String, timestamp: Int) { self.title = title; self.timestamp = timestamp }
  }
  public var slug: String
  public var number: Int?
  public var title: String
  public var snippet: String?
  public var hits: [Hit]
}

public struct SearchPage: Equatable, Sendable {
  public var total: Int?
  public var results: [SearchResult]
}
