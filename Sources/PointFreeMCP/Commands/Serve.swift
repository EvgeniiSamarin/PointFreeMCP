import ArgumentParser
import Foundation
import Logging
import MCP
import PointFreeKit

struct Serve: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Run the MCP server over stdio (default).")

  func run() async throws {
    // stdout принадлежит JSON-RPC; все логи только в stderr.
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardError(label: label)
      handler.logLevel = .warning
      return handler
    }
    let catalog = ToolCatalog()
    let server = try await MCPServerFactory.make(catalog: catalog)
    let transport = StdioTransport(logger: Logger(label: "pointfree-mcp.stdio"))
    try await server.start(transport: transport)
    await server.waitUntilCompleted()
  }
}
