import Foundation

public actor MemoryCache<Value: Sendable> {
  private struct Entry { var value: Value; var storedAt: Date; var order: UInt64 }

  private let ttl: TimeInterval
  private let maxEntries: Int
  private let now: @Sendable () -> Date
  private var entries: [String: Entry] = [:]
  private var counter: UInt64 = 0

  public init(ttl: TimeInterval, maxEntries: Int, now: @escaping @Sendable () -> Date = { Date() }) {
    self.ttl = ttl; self.maxEntries = maxEntries; self.now = now
  }

  public func value(for key: String) -> Value? {
    guard let entry = entries[key] else { return nil }
    if now().timeIntervalSince(entry.storedAt) >= ttl {
      entries[key] = nil
      return nil
    }
    return entry.value
  }

  public func set(_ value: Value, for key: String) {
    counter += 1
    entries[key] = Entry(value: value, storedAt: now(), order: counter)
    while entries.count > maxEntries, let oldest = entries.min(by: { $0.value.order < $1.value.order }) {
      entries[oldest.key] = nil
    }
  }

  public func removeAll() { entries.removeAll() }
}
