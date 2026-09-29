import Foundation
import MCP
import PointFreeKit

enum MCPServerFactory {
  static func make(catalog: ToolCatalog) async throws -> Server {
    let server = Server(
      name: "pointfree",
      version: PointFreeKit.version,
      capabilities: .init(tools: .init(listChanged: false))
    )

    let tools: [Tool] = try ToolDefinitions.all.map { def in
      let schema = try JSONDecoder().decode(Value.self, from: Data(def.inputSchemaJSON.utf8))
      return Tool(name: def.name, description: def.description, inputSchema: schema)
    }

    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: tools)
    }

    await server.withMethodHandler(CallTool.self) { params in
      let arguments: ToolArguments
      if let raw = params.arguments {
        let data = try JSONEncoder().encode(raw)
        arguments = try JSONDecoder().decode(ToolArguments.self, from: data)
      } else {
        arguments = ToolArguments()
      }
      let output = await catalog.call(name: params.name, arguments: arguments)
      return .init(content: [.text(text: output.text, annotations: nil, _meta: nil)], isError: output.isError)
    }

    return server
  }
}
