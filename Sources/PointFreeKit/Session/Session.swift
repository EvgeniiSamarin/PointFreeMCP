import Foundation

public struct Session: Codable, Equatable, Sendable {
  public var cookie: String
  public var expiresAt: Date
  public var savedAt: Date

  public init(cookie: String, expiresAt: Date, savedAt: Date) {
    self.cookie = cookie; self.expiresAt = expiresAt; self.savedAt = savedAt
  }

  public func isExpired(now: Date) -> Bool { now >= expiresAt }
}
