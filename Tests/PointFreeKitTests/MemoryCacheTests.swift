import Foundation
import Testing
@testable import PointFreeKit

@Test func cacheExpiresByTTLAndEvictsOldest() async {
  // SAFETY: тест обращается к объекту последовательно из одного таска; синхронизация не нужна.
  final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 0) }
  let clock = Clock()
  let cache = MemoryCache<String>(ttl: 10, maxEntries: 2, now: { clock.now })

  await cache.set("a", for: "A")
  #expect(await cache.value(for: "A") == "a")

  clock.now = Date(timeIntervalSince1970: 11)
  #expect(await cache.value(for: "A") == nil)

  await cache.set("a", for: "A")
  await cache.set("b", for: "B")
  await cache.set("c", for: "C")   // вытесняет A
  #expect(await cache.value(for: "A") == nil)
  #expect(await cache.value(for: "B") == "b")
  #expect(await cache.value(for: "C") == "c")

  await cache.removeAll()
  #expect(await cache.value(for: "B") == nil)
}
