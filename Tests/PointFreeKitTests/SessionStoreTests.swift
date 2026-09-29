import Foundation
import Testing
@testable import PointFreeKit

@Test func sessionStoreRoundTripsAndProtectsFile() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let store = SessionStore.file(in: dir)
  #expect(try store.load() == nil)

  let session = Session(cookie: "abc==", expiresAt: Date(timeIntervalSince1970: 2_000_000_000), savedAt: Date(timeIntervalSince1970: 1_000_000_000))
  try store.save(session)
  #expect(try store.load() == session)

  let attrs = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("session.json").path)
  #expect((attrs[.posixPermissions] as? Int) == 0o600)
  let dirAttrs = try FileManager.default.attributesOfItem(atPath: dir.path)
  #expect((dirAttrs[.posixPermissions] as? Int) == 0o700)

  try store.clear()
  #expect(try store.load() == nil)
  try store.clear()  // повторный clear не падает
}

@Test func sessionKnowsWhenExpired() {
  let s = Session(cookie: "x", expiresAt: Date(timeIntervalSince1970: 100), savedAt: Date(timeIntervalSince1970: 0))
  #expect(s.isExpired(now: Date(timeIntervalSince1970: 101)))
  #expect(!s.isExpired(now: Date(timeIntervalSince1970: 99)))
}

@Test func sessionStoreLeavesExistingDirectoryModeAlone() throws {
  let fm = FileManager.default
  let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
  try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
  defer { try? fm.removeItem(at: dir) }

  try SessionStore.file(in: dir).save(Session(cookie: "x", expiresAt: Date(timeIntervalSince1970: 2_000_000_000), savedAt: Date(timeIntervalSince1970: 0)))
  let dirAttrs = try fm.attributesOfItem(atPath: dir.path)
  #expect((dirAttrs[.posixPermissions] as? Int) == 0o755)
  let fileAttrs = try fm.attributesOfItem(atPath: dir.appendingPathComponent("session.json").path)
  #expect((fileAttrs[.posixPermissions] as? Int) == 0o600)
}
