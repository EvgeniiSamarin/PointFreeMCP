import ArgumentParser
import Dependencies
import PointFreeKit

struct Logout: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Delete the saved pointfree.co session.")

  func run() throws {
    @Dependency(\.sessionStore) var store
    try store.clear()
    print("Session removed.")
  }
}
