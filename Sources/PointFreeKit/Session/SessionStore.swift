import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct SessionStore: Sendable {
  public var load: @Sendable () throws -> Session?
  public var save: @Sendable (_ session: Session) throws -> Void
  public var clear: @Sendable () throws -> Void
}

extension SessionStore {
  public static func file(in directory: URL) -> SessionStore {
    let fileURL = directory.appendingPathComponent("session.json")
    // FileManager не Sendable: берём FileManager.default внутри каждого замыкания.
    return SessionStore(
      load: {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Session.self, from: data)
      },
      save: { session in
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(session)
        // Файл создаётся сразу с правами 0600, без окна с правами по umask.
        guard fm.createFile(atPath: fileURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
          throw CocoaError(.fileWriteUnknown)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
      },
      clear: {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) { try fm.removeItem(at: fileURL) }
      }
    )
  }

  public static var defaultDirectory: URL {
    if let custom = ProcessInfo.processInfo.environment["POINTFREE_MCP_HOME"], !custom.isEmpty {
      return URL(fileURLWithPath: custom, isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pointfree-mcp", isDirectory: true)
  }
}

extension SessionStore: DependencyKey {
  public static let liveValue = SessionStore.file(in: SessionStore.defaultDirectory)
}

extension DependencyValues {
  public var sessionStore: SessionStore {
    get { self[SessionStore.self] }
    set { self[SessionStore.self] = newValue }
  }
}
