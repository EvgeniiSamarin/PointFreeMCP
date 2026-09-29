import Dependencies
import DependenciesMacros
import Foundation

public enum LoginOutcome: Equatable, Sendable {
  case success
  case cancelled
  case failed(String)
}

@DependencyClient
public struct LoginLauncher: Sendable {
  public var run: @Sendable () async throws -> LoginOutcome
}

extension LoginLauncher: DependencyKey {
  /// Запускает тот же исполняемый файл с подкомандой `login`. Дочерний процесс сам
  /// ограничивает ожидание 290 с (код 3); страховочный таймер здесь — 320 с.
  /// Коды выхода `login`: 0 сохранено, 1 отменено, 2 cookie отвергнута, 3 таймаут, 4 ошибка.
  public static let liveValue = LoginLauncher {
    let executable = Bundle.main.executableURL
      ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).standardizedFileURL
    let process = Process()
    process.executableURL = executable
    process.arguments = ["login", "--timeout", "290"]
    process.standardInput = FileHandle.nullDevice  // stdin сервера — канал MCP, дочернему процессу он не нужен
    process.standardOutput = FileHandle.standardError
    process.standardError = FileHandle.standardError
    let watchdog = Task {
      try? await Task.sleep(for: .seconds(320))
      if process.isRunning { process.terminate() }
    }
    defer { watchdog.cancel() }
    // terminationHandler ставится до run(), иначе быстрый выход потеряет continuation.
    // Отмена вызова инструмента закрывает окно входа (SIGTERM дочернему процессу).
    let status: Int32 = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
        process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        do { try process.run() } catch { continuation.resume(throwing: error) }
      }
    } onCancel: {
      if process.isRunning { process.terminate() }
    }
    switch status {
    case 0: return .success
    case 1: return .cancelled
    case 2: return .failed("pointfree.co rejected the session cookie")
    case 3: return .failed("timed out waiting for the browser login")
    case 4: return .failed("error during login; see the server's stderr")
    default: return .failed("login process exited with status \(status)")
    }
  }
}

extension DependencyValues {
  public var loginLauncher: LoginLauncher {
    get { self[LoginLauncher.self] }
    set { self[LoginLauncher.self] = newValue }
  }
}
