import Foundation

public struct ToolArguments: Decodable, Sendable {
  public enum Value: Decodable, Equatable, Sendable {
    case string(String), int(Int), double(Double), bool(Bool), null, other

    public init(from decoder: Decoder) throws {
      let c = try decoder.singleValueContainer()
      if c.decodeNil() { self = .null }
      else if let b = try? c.decode(Bool.self) { self = .bool(b) }
      else if let i = try? c.decode(Int.self) { self = .int(i) }
      else if let d = try? c.decode(Double.self) { self = .double(d) }
      else if let s = try? c.decode(String.self) { self = .string(s) }
      else { self = .other }
    }
  }

  public var values: [String: Value]

  public init(values: [String: Value] = [:]) { self.values = values }

  public init(from decoder: Decoder) throws {
    values = try decoder.singleValueContainer().decode([String: Value].self)
  }

  public func string(_ key: String) -> String? {
    switch values[key] {
    case .string(let s): return s.isEmpty ? nil : s
    case .int(let i): return String(i)
    default: return nil
    }
  }

  public func int(_ key: String) -> Int? {
    switch values[key] {
    case .int(let i): return i
    case .double(let d): return Int(d)
    case .string(let s): return Int(s)
    default: return nil
    }
  }

  public func bool(_ key: String) -> Bool? {
    switch values[key] {
    case .bool(let b): return b
    case .string(let s): return Bool(s)
    default: return nil
    }
  }
}
