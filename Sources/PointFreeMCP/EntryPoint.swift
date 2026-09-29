import AppKit
import ArgumentParser
import Dependencies
import Foundation
import PointFreeKit

/// Точка входа. Окно входа (WKWebView) должно крутиться в NSApp.run() на настоящем главном потоке,
/// а не внутри async-задачи: вложенный цикл внутри блока главной очереди не даёт WebKit доставлять
/// IPC (делегаты молчат, страница пустая). Поэтому `login` без --cookie показывает окно здесь, синхронно,
/// а результат передаётся асинхронной команде через `Login.windowOutcome`.
@main
enum EntryPoint {
  static func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "login",
      let login = try? Login.parse(Array(args.dropFirst())),
      login.cookie == nil
    {
      FileHandle.standardError.write(Data("Opening pointfree.co login window…\n".utf8))
      Login.windowOutcome = MainActor.assumeIsolated {
        @Dependency(\.pointFreeClient) var client
        let validate = client.validateSession
        return LoginWindowController(validate: { try await validate($0) }).run(timeout: login.timeout)
      }
    }
    Task {
      await PointFreeMCPCommand.main()
      exit(0)  // main() возвращается только при успехе; при ошибке ArgumentParser сам вызывает exit
    }
    dispatchMain()
  }
}
