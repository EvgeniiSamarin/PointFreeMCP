import Foundation

public struct SearchQuery: Equatable, Sendable {
  public enum Scope: String, CaseIterable, Sendable { case code, dialogue, titles }
  public enum Access: String, CaseIterable, Sendable { case free, subscriberOnly = "subscriber-only" }
  public enum Sort: String, CaseIterable, Sendable { case newest, oldest }

  public var query: String
  public var scope: Scope?
  public var access: Access?
  public var sort: Sort?

  public init(query: String, scope: Scope? = nil, access: Access? = nil, sort: Sort? = nil) {
    self.query = query; self.scope = scope; self.access = access; self.sort = sort
  }

  public var url: URL {
    guard var components = URLComponents(url: PointFreeClient.baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false) else {
      preconditionFailure("invalid search URL")
    }
    var items = [URLQueryItem(name: "q", value: query)]
    if let scope { items.append(URLQueryItem(name: "scope", value: scope.rawValue)) }
    if let access { items.append(URLQueryItem(name: "access", value: access.rawValue)) }
    if let sort { items.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
    components.queryItems = items
    // URLComponents оставляет "&", "+" и "#" в значениях; кодируем их явно.
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+#=")
    components.percentEncodedQuery = items.map { item in
      let value = item.value?.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
      return "\(item.name)=\(value)"
    }.joined(separator: "&")
    guard let url = components.url else { preconditionFailure("invalid search URL for query") }
    return url
  }

  public var cacheKey: String { url.absoluteString }
}
