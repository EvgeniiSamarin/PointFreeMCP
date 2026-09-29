public struct CollectionSummary: Equatable, Sendable {
  public var slug: String, title: String, description: String?
  public init(slug: String, title: String, description: String?) { self.slug = slug; self.title = title; self.description = description }
}
public struct CollectionSection: Equatable, Sendable {
  public var slug: String, title: String
  public init(slug: String, title: String) { self.slug = slug; self.title = title }
}
public struct SectionEpisode: Equatable, Sendable {
  public var number: Int, slug: String, title: String, duration: String?
  public init(number: Int, slug: String, title: String, duration: String?) { self.number = number; self.slug = slug; self.title = title; self.duration = duration }
}
public struct SectionGroup: Equatable, Sendable {
  public var heading: String, episodes: [SectionEpisode]
  public init(heading: String, episodes: [SectionEpisode]) { self.heading = heading; self.episodes = episodes }
}
