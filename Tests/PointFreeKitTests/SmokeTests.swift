import Testing
@testable import PointFreeKit

@Test func versionIsSet() {
  #expect(PointFreeKit.version == "0.1.0")
  #expect(PointFreeKit.userAgent == "pointfree-mcp/0.1.0")
}
