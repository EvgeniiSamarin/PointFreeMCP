import ArgumentParser
import Dependencies
import Foundation
import PointFreeKit

struct Login: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Sign in to pointfree.co with GitHub in a browser window.")

  @Option(help: "Save a pf_session cookie value copied from your browser instead of opening a window.")
  var cookie: String?

  @Option(help: "Seconds to wait for the login to complete.")
  var timeout: Double = 300

  /// Результат окна входа; заполняется в EntryPoint.main() до старта async-команды.
  nonisolated(unsafe) static var windowOutcome: LoginWindowController.Result?

  @MainActor
  func run() async throws {
    do {
      try await performLogin()
    } catch let code as ExitCode {
      throw code
    } catch {
      FileHandle.standardError.write(Data("Login failed: \(error)\n".utf8))
      throw ExitCode(4)
    }
  }

  @MainActor
  private func performLogin() async throws {
    @Dependency(\.sessionStore) var store
    @Dependency(\.pointFreeClient) var client

    let value: String
    let expires: Date?
    if let cookie {
      value = cookie
      expires = nil
    } else {
      // Окно уже показано из EntryPoint.main() на настоящем главном потоке (вне async-задачи), см. EntryPoint.swift.
      guard let outcome = Login.windowOutcome else {
        FileHandle.standardError.write(Data("Login window did not run.\n".utf8))
        throw ExitCode(4)
      }
      switch outcome {
      case .cookie(let v, let e): value = v; expires = e
      case .cancelled:
        FileHandle.standardError.write(Data("Login cancelled.\n".utf8))
        throw ExitCode(1)
      case .timedOut:
        FileHandle.standardError.write(Data("Login timed out.\n".utf8))
        throw ExitCode(3)
      }
    }

    guard try await client.validateSession(value) else {
      FileHandle.standardError.write(Data("pointfree.co rejected the session cookie.\n".utf8))
      throw ExitCode(2)
    }
    let now = Date()
    let session = Session(cookie: value, expiresAt: expires ?? now.addingTimeInterval(7 * 24 * 3600), savedAt: now)
    try store.save(session)
    FileHandle.standardError.write(Data("Signed in. Session saved until \(session.expiresAt).\n".utf8))
  }
}
