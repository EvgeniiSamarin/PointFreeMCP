import ArgumentParser
import Dependencies
import PointFreeKit

struct Logout: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Delete the saved pointfree.co session.")

  func run() throws {
    @Dependency(\.sessionStore) var store
    // Нечитаемый файл тоже считаем сессией: clear() всё равно его удалит.
    let hadSession: Bool
    do { hadSession = try store.load() != nil } catch { hadSession = true }
    try store.clear()
    print(hadSession ? "Session removed." : "No saved session.")
  }
}
