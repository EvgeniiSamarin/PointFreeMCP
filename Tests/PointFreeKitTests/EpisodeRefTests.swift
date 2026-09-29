import Testing
@testable import PointFreeKit

private let episodeRefCases: [(String, Int, String?, SectionRef?)] = [
  ("381", 381, nil, nil),
  ("ep381-designing-for-isolation-naively", 381, "ep381-designing-for-isolation-naively", nil),
  ("EP381-Designing", 381, "ep381-designing", nil),
  ("https://www.pointfree.co/episodes/ep381-designing-for-isolation-naively#t349", 381, "ep381-designing-for-isolation-naively", .timestamp(349)),
  ("https://www.pointfree.co/episodes/ep381-x/?utm=1", 381, "ep381-x", nil),
  ("/episodes/22", 22, nil, nil),
]

@Test(arguments: episodeRefCases)
func parsesEpisodeRefs(raw: String, number: Int, slug: String?, section: SectionRef?) throws {
  let ref = try #require(EpisodeRef.parse(raw))
  #expect(ref.number == number)
  #expect(ref.slug == slug)
  #expect(ref.section == section)
}

@Test(arguments: ["", "functions", "https://www.pointfree.co/collections/x", "ep-foo"])
func rejectsBadRefs(raw: String) {
  #expect(EpisodeRef.parse(raw) == nil)
}

@Test func pathComponentPrefersSlug() {
  #expect(EpisodeRef.parse("381")?.pathComponent == "381")
  #expect(EpisodeRef.parse("ep381-a-b")?.pathComponent == "ep381-a-b")
}

@Test func parsesSectionRefs() {
  #expect(SectionRef.parse("t349") == .timestamp(349))
  #expect(SectionRef.parse("5:49") == .timestamp(349))
  #expect(SectionRef.parse("1:02:03") == .timestamp(3723))
  #expect(SectionRef.parse("#introduction") == .slug("introduction"))
  #expect(SectionRef.parse("Introduction") == .slug("introduction"))
}
