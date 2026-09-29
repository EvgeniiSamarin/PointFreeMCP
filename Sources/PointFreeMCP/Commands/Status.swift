import ArgumentParser
import Dependencies
import Foundation
import PointFreeKit

struct Status: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Show the saved pointfree.co session.")

  func run() async throws {
    @Dependency(\.sessionStore) var store
    @Dependency(\.pointFreeClient) var client
    guard let session = try store.load() else {
      print("Not signed in. Run `pointfree-mcp login`.")
      return
    }
    if session.isExpired(now: Date()) {
      print("Session expired at \(session.expiresAt). Run `pointfree-mcp login`.")
      return
    }
    let valid = try await client.validateSession(session.cookie)
    print(valid ? "Signed in; session valid until \(session.expiresAt)." : "Session file exists but pointfree.co rejected it. Run `pointfree-mcp login`.")
  }
}
