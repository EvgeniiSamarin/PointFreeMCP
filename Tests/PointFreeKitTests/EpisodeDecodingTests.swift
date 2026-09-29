import Foundation
import Testing
@testable import PointFreeKit

@Test func decodesEpisodeList() throws {
  let episodes = try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: fixture("episodes.json"))
  #expect(episodes.count == 3)
  let first = try #require(episodes.first)
  #expect(first.id == 381)
  #expect(first.subscriberOnly)
  #expect(first.durationLabel == "16:48")
  let calendar = Calendar(identifier: .gregorian)
  let utc = try #require(TimeZone(identifier: "UTC"))
  let year = calendar.dateComponents(in: utc, from: first.publishedAt).year
  #expect(year == 2026)
}

@Test func decodesEpisodeDetailAndIgnoresVideo() throws {
  let detail = try PointFreeJSON.decoder.decode(EpisodeDetail.self, from: fixture("episode-381.json"))
  #expect(detail.codeSampleDirectory == "0381-isolation-design-pt2")
  #expect(detail.references.count == 1)
  #expect(detail.references[0].author == "Gary Bernhardt")
  #expect(detail.codeSampleURL?.absoluteString == "https://github.com/pointfreeco/episode-code-samples/tree/main/0381-isolation-design-pt2")
  #expect(detail.pageURL.absoluteString == "https://www.pointfree.co/episodes/381")
}
