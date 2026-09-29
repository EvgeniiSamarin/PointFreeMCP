import ArgumentParser
import PointFreeKit

@main
struct PointFreeMCPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pointfree-mcp",
    abstract: "MCP server for pointfree.co",
    version: PointFreeKit.version,
    subcommands: [Serve.self, Status.self, Logout.self, Login.self],
    defaultSubcommand: Serve.self
  )
}
