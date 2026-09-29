import Dependencies
import DependenciesMacros
import Foundation

public struct HTTPResponse: Equatable, Sendable {
  public var statusCode: Int
  public var body: Data
  public var headers: [String: String]

  public init(statusCode: Int, body: Data, headers: [String: String] = [:]) {
    self.statusCode = statusCode; self.body = body; self.headers = headers
  }
}

@DependencyClient
public struct HTTPClient: Sendable {
  public var fetch: @Sendable (_ request: URLRequest) async throws -> HTTPResponse
}

extension HTTPClient: DependencyKey {
  public static let liveValue: HTTPClient = {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.timeoutIntervalForRequest = 20
    config.httpAdditionalHeaders = ["User-Agent": PointFreeKit.userAgent]
    let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    return HTTPClient { request in
      do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PointFreeError.network("non-HTTP response") }
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields { headers[String(describing: k).lowercased()] = String(describing: v) }
        return HTTPResponse(statusCode: http.statusCode, body: data, headers: headers)
      } catch let error as PointFreeError {
        throw error
      } catch {
        throw PointFreeError.network(error.localizedDescription)
      }
    }
  }()
}

extension DependencyValues {
  public var httpClient: HTTPClient {
    get { self[HTTPClient.self] }
    set { self[HTTPClient.self] = newValue }
  }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? { nil }
}
