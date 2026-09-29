import Foundation

public enum PointFreeError: Error, Equatable, Sendable {
  case network(String)
  case httpStatus(Int, URL)
  case notFound(URL)
  case decoding(String)
  case structureChanged(String, URL?)
  case loginRequired
  case sessionExpired
  case subscriptionRequired
  case invalidArgument(String)
  case loginFailed(String)

  public var userMessage: String {
    switch self {
    case .network(let m): return "Network error: \(m)"
    case .httpStatus(let code, let url): return "pointfree.co responded with HTTP \(code) for \(url.absoluteString)"
    case .notFound(let url): return "Not found: \(url.absoluteString)"
    case .decoding(let m): return "Could not decode response: \(m)"
    case .structureChanged(let what, let url):
      return "pointfree.co markup changed (\(what))" + (url.map { " at \($0.absoluteString)" } ?? "") + ". Update pointfree-mcp."
    case .loginRequired: return "This episode is for Point-Free members. Call the `login` tool to sign in with GitHub, then retry."
    case .sessionExpired: return "Your Point-Free session expired. Call the `login` tool to sign in again, then retry."
    case .subscriptionRequired: return "Signed in, but the transcript is truncated: the account has no active Point-Free subscription, or the session is stale. Call `login` with force=true to re-authenticate."
    case .invalidArgument(let m): return "Invalid argument: \(m)"
    case .loginFailed(let m): return "Login failed: \(m)"
    }
  }
}
