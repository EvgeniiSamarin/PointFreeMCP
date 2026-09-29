import ArgumentParser
import PointFreeKit

@main
struct PointFreeMCPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pointfree-mcp",
    abstract: "MCP server for pointfree.co",
    version: PointFreeKit.version
  )

  func run() async throws {
    print("pointfree-mcp \(PointFreeKit.version)")
  }
}
