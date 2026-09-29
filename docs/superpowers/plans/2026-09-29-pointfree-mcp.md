# PointFreeMCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Локальный stdio MCP-сервер на Swift, который отдаёт Claude Code поиск, метаданные, транскрипты и коллекции pointfree.co по запросу, с входом через GitHub в окне WKWebView.

**Architecture:** Библиотека `PointFreeKit` (модели, HTTP-клиент, парсеры SwiftSoup, рендер markdown, хранилище сессии, обработчики инструментов) без AppKit и без MCP-типов; исполняемый `pointfree-mcp` связывает её с `MCP` swift-sdk (команда `serve`) и содержит AppKit-окно входа (команда `login`). Все внешние эффекты — dependencies из swift-dependencies, в тестах подменяются.

**Tech Stack:** Swift 6.2 tools, macOS 26, modelcontextprotocol/swift-sdk 0.12, SwiftSoup 2.13, Foundation XMLParser (Atom-фид блога), swift-argument-parser 1.8, swift-dependencies 1.17, swift-log 1.15, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-29-pointfree-mcp-design.md`

## Execution Order

Задачи выполняются в порядке 1–9, **11, 10**, 12, 13, **16**, 14, **17**, 15: Task 10 (рендер) использует `BlogPost` из Task 11, а Task 11 зависит только от Tasks 4 и 7.

## Global Constraints

- Платформа только macOS 26+: `platforms: [.macOS(.v26)]`, `swiftLanguageModes: [.v6]`.
- Транскрипты не пишутся на диск и не логируются; кэш только в памяти процесса.
- Фикстуры в `Tests/PointFreeKitTests/Fixtures/` синтетические: структура сайта, заглушечный текст. Реальные страницы только в `Tests/live/` (в `.gitignore`, вне ресурсов тестового таргета).
- Сервер пишет в stdout только JSON-RPC; все логи и диагностика — в stderr.
- Cookie `pf_session` отправляется только на хост `www.pointfree.co`.
- Файл сессии `~/.pointfree-mcp/session.json` (переопределяется `POINTFREE_MCP_HOME`), права 0600, каталог 0700.
- User-Agent: `pointfree-mcp/0.1.0`. Таймаут запроса 20 с. Редиректы не следуются.
- Инструменты возвращают один текстовый блок markdown; ошибки — `isError: true` с понятным текстом.
- Лицензия кода — MIT (`LICENSE` в корне).

## Review Focus

1. Ссылка на эпизод в необычной форме (`EP381`, URL с `?` и завершающим `/`, `#t349`) должна разрешаться в тот же эпизод, а не в «не найдено» — тест в Task 3.
2. Поисковый запрос с пробелами, `&`, `+`, `#` должен корректно кодироваться в URL — тест в Task 6.
3. Несуществующий номер эпизода (`/api/episodes/9999` отдаёт HTML 404) должен давать ошибку «не найдено», а не падение декодера JSON — тест в Task 6.
4. Код в `<pre>` с сущностями `&lt;`, `&amp;` и вложенными `<span>` должен выводиться как исходный текст без потери переносов строк — тест в Task 7.
5. Платный эпизод при наличии cookie без активной подписки (страница обрезана) должен давать понятную ошибку и не удалять валидную сессию — тест в Task 11.

---

### Task 1: Скелет пакета и сборка

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `Sources/PointFreeKit/PointFreeKit.swift`
- Create: `Sources/PointFreeMCP/PointFreeMCPCommand.swift`
- Create: `Tests/PointFreeKitTests/SmokeTests.swift`

**Interfaces:**
- Produces: targets `PointFreeKit`, `PointFreeMCP` (исполняемый `pointfree-mcp`), `PointFreeKitTests`; константа `PointFreeKit.version = "0.1.0"`.

- [ ] **Step 1: Package.swift**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "PointFreeMCP",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "pointfree-mcp", targets: ["PointFreeMCP"]),
    .library(name: "PointFreeKit", targets: ["PointFreeKit"]),
  ],
  dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.9"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.17.1"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.15.1"),
  ],
  targets: [
    .target(
      name: "PointFreeKit",
      dependencies: [
        .product(name: "SwiftSoup", package: "SwiftSoup"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .executableTarget(
      name: "PointFreeMCP",
      dependencies: [
        "PointFreeKit",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    .testTarget(
      name: "PointFreeKitTests",
      dependencies: [
        "PointFreeKit",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: .gitignore и LICENSE**

`.gitignore`:
```
.build/
.swiftpm/
*.xcodeproj
xcuserdata/
.DS_Store
Tests/live/
```

`LICENSE` — стандартный текст MIT, год 2026, правообладатель «Evgeniy Samarin».

- [ ] **Step 3: Минимальные исходники**

`Sources/PointFreeKit/PointFreeKit.swift`:
```swift
public enum PointFreeKit {
  public static let version = "0.1.0"
  public static let userAgent = "pointfree-mcp/\(version)"
}
```

`Sources/PointFreeMCP/PointFreeMCPCommand.swift`:
```swift
import ArgumentParser
import PointFreeKit

@main
struct PointFreeMCPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pointfree-mcp",
    abstract: "MCP server for pointfree.co",
    version: PointFreeKit.version
  )

  func run() async throws {
    print("pointfree-mcp \(PointFreeKit.version)")
  }
}
```

`Tests/PointFreeKitTests/SmokeTests.swift`:
```swift
import Testing
@testable import PointFreeKit

@Test func versionIsSet() {
  #expect(PointFreeKit.version == "0.1.0")
  #expect(PointFreeKit.userAgent == "pointfree-mcp/0.1.0")
}
```

Создать пустой каталог фикстур: `Tests/PointFreeKitTests/Fixtures/.keep`.

- [ ] **Step 4: Сборка и тест**

Run: `swift build && swift test`
Expected: сборка успешна, 1 тест пройден. Если `.macOS(.v26)` не принимается — обновить tools-version до той, что поддерживает Xcode 26, но не опускать платформу.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved .gitignore LICENSE Sources Tests docs
git commit -m "chore: scaffold PointFreeMCP package with spec and plan"
```

---

### Task 2: Модели эпизодов и декодирование JSON API

**Files:**
- Create: `Sources/PointFreeKit/Models/Episode.swift`
- Create: `Tests/PointFreeKitTests/Fixtures/episodes.json`
- Create: `Tests/PointFreeKitTests/Fixtures/episode-381.json`
- Create: `Tests/PointFreeKitTests/Support/Fixtures.swift`
- Test: `Tests/PointFreeKitTests/EpisodeDecodingTests.swift`

**Interfaces:**
- Produces: `EpisodeSummary`, `EpisodeDetail`, `Reference`, `PointFreeJSON.decoder`, `fixture(_:)` в тестах, `EpisodeSummary.durationLabel`, `EpisodeDetail.pageURL`, `EpisodeDetail.codeSampleURL`.

- [ ] **Step 1: Фикстуры**

`Tests/PointFreeKitTests/Fixtures/episodes.json` (даты — секунды от 2001-01-01, как отдаёт сайт):
```json
[
  {"publishedAt":812246400,"id":381,"image":"https://example.invalid/0381.jpeg","subscriberOnly":true,"sequence":381,"title":"Designing for Isolation: Naively","blurb":"Blurb 381","length":1008},
  {"publishedAt":809827200,"id":379,"image":"https://example.invalid/0379.jpeg","subscriberOnly":false,"sequence":379,"title":"WWDC26: The @LazyState Macro","blurb":"Blurb 379","length":1543},
  {"publishedAt":538899069,"id":1,"image":"https://example.invalid/0001.jpeg","subscriberOnly":false,"sequence":1,"title":"Functions","blurb":"Blurb 1","length":1219}
]
```

`Tests/PointFreeKitTests/Fixtures/episode-381.json`:
```json
{
  "image":"https://example.invalid/0381.jpeg",
  "references":[{"blurb":"> Note text","link":"https://example.invalid/fcis","publishedAt":363744000,"title":"Functional Core, Imperative Shell","author":"Gary Bernhardt"}],
  "subscriberOnly":true,
  "video":{"id":"abc","bytesLength":1,"downloadUrl":{"s3":{"hd1080":"x","sd540":"y","hd720":"z"}}},
  "publishedAt":812246400,
  "id":381,
  "codeSampleDirectory":"0381-isolation-design-pt2",
  "blurb":"Blurb 381",
  "title":"Designing for Isolation: Naively",
  "sequence":381,
  "previousEpisodesInCollection":[],
  "length":1008
}
```

`Tests/PointFreeKitTests/Support/Fixtures.swift`:
```swift
import Foundation

func fixture(_ name: String) throws -> Data {
  let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
  guard let url else { throw FixtureError.missing(name) }
  return try Data(contentsOf: url)
}

func fixtureString(_ name: String) throws -> String {
  String(decoding: try fixture(name), as: UTF8.self)
}

enum FixtureError: Error { case missing(String) }
```

- [ ] **Step 2: Тест декодирования**

`Tests/PointFreeKitTests/EpisodeDecodingTests.swift`:
```swift
import Foundation
import Testing
@testable import PointFreeKit

@Test func decodesEpisodeList() throws {
  let episodes = try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: fixture("episodes.json"))
  #expect(episodes.count == 3)
  let first = try #require(episodes.first)
  #expect(first.id == 381)
  #expect(first.subscriberOnly)
  #expect(first.durationLabel == "16:48")
  let calendar = Calendar(identifier: .gregorian)
  let year = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: first.publishedAt).year
  #expect(year == 2026)
}

@Test func decodesEpisodeDetailAndIgnoresVideo() throws {
  let detail = try PointFreeJSON.decoder.decode(EpisodeDetail.self, from: fixture("episode-381.json"))
  #expect(detail.codeSampleDirectory == "0381-isolation-design-pt2")
  #expect(detail.references.count == 1)
  #expect(detail.references[0].author == "Gary Bernhardt")
  #expect(detail.codeSampleURL?.absoluteString == "https://github.com/pointfreeco/episode-code-samples/tree/main/0381-isolation-design-pt2")
  #expect(detail.pageURL.absoluteString == "https://www.pointfree.co/episodes/381")
}
```

- [ ] **Step 3: Запустить тест, убедиться, что не компилируется**

Run: `swift test --filter EpisodeDecodingTests`
Expected: ошибка компиляции — типы не определены.

- [ ] **Step 4: Модели**

`Sources/PointFreeKit/Models/Episode.swift`:
```swift
import Foundation

public enum PointFreeJSON {
  /// Сайт кодирует даты стратегией по умолчанию JSONEncoder: секунды от 2001-01-01.
  public static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .deferredToDate
    return decoder
  }()
}

public struct EpisodeSummary: Codable, Equatable, Sendable, Identifiable {
  public var id: Int
  public var sequence: Int
  public var title: String
  public var blurb: String
  public var length: Int
  public var publishedAt: Date
  public var subscriberOnly: Bool
  public var image: String

  public init(id: Int, sequence: Int, title: String, blurb: String, length: Int, publishedAt: Date, subscriberOnly: Bool, image: String) {
    self.id = id; self.sequence = sequence; self.title = title; self.blurb = blurb
    self.length = length; self.publishedAt = publishedAt; self.subscriberOnly = subscriberOnly; self.image = image
  }

  public var durationLabel: String { Timecode.label(seconds: length) }
  public var accessLabel: String { subscriberOnly ? "Members only" : "Free" }
}

public struct Reference: Codable, Equatable, Sendable {
  public var title: String
  public var link: String?
  public var author: String?
  public var blurb: String?
  public var publishedAt: Date?
}

public struct EpisodeDetail: Codable, Equatable, Sendable, Identifiable {
  public var id: Int
  public var sequence: Int
  public var title: String
  public var blurb: String
  public var length: Int
  public var publishedAt: Date
  public var subscriberOnly: Bool
  public var image: String
  public var codeSampleDirectory: String?
  public var references: [Reference]

  public var durationLabel: String { Timecode.label(seconds: length) }
  public var accessLabel: String { subscriberOnly ? "Members only" : "Free" }
  public var pageURL: URL { URL(string: "https://www.pointfree.co/episodes/\(id)")! }
  public var codeSampleURL: URL? {
    codeSampleDirectory.flatMap {
      URL(string: "https://github.com/pointfreeco/episode-code-samples/tree/main/\($0)")
    }
  }
}

public enum Timecode {
  /// 68 -> "1:08", 3723 -> "1:02:03"
  public static func label(seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0
      ? String(format: "%d:%02d:%02d", h, m, s)
      : String(format: "%d:%02d", m, s)
  }

  /// "1:08" -> 68, "1:02:03" -> 3723, "t349" -> 349, "349" -> 349; иначе nil
  public static func seconds(from text: String) -> Int? {
    var raw = text.trimmingCharacters(in: .whitespaces)
    if raw.hasPrefix("t") { raw.removeFirst() }
    if let n = Int(raw) { return n }
    let parts = raw.split(separator: ":").map { Int($0) }
    guard parts.count >= 2, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
    let nums = parts.compactMap { $0 }
    return nums.reduce(0) { $0 * 60 + $1 }
  }
}
```

- [ ] **Step 5: Тесты проходят**

Run: `swift test --filter EpisodeDecodingTests`
Expected: 2 теста PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/PointFreeKit/Models Tests/PointFreeKitTests
git commit -m "feat: episode models and JSON API decoding"
```

---

### Task 3: Разбор ссылок на эпизод и на главу

**Files:**
- Create: `Sources/PointFreeKit/Models/EpisodeRef.swift`
- Test: `Tests/PointFreeKitTests/EpisodeRefTests.swift`

**Interfaces:**
- Produces: `EpisodeRef { number: Int; slug: String?; section: SectionRef? }`, `EpisodeRef.parse(_ raw: String) -> EpisodeRef?`, `EpisodeRef.pathComponent: String`, `SectionRef { case timestamp(Int), slug(String) }`, `SectionRef.parse(_:)`.

- [ ] **Step 1: Тест**

```swift
import Testing
@testable import PointFreeKit

private let episodeRefCases: [(String, Int, String?, SectionRef?)] = [
  ("381", 381, nil, nil),
  ("ep381-designing-for-isolation-naively", 381, "ep381-designing-for-isolation-naively", nil),
  ("EP381-Designing", 381, "ep381-designing", nil),
  ("https://www.pointfree.co/episodes/ep381-designing-for-isolation-naively#t349", 381, "ep381-designing-for-isolation-naively", .timestamp(349)),
  ("https://www.pointfree.co/episodes/ep381-x/?utm=1", 381, "ep381-x", nil),
  ("/episodes/22", 22, nil, nil),
]

@Test(arguments: episodeRefCases)
func parsesEpisodeRefs(raw: String, number: Int, slug: String?, section: SectionRef?) throws {
  let ref = try #require(EpisodeRef.parse(raw))
  #expect(ref.number == number)
  #expect(ref.slug == slug)
  #expect(ref.section == section)
}

@Test(arguments: ["", "functions", "https://www.pointfree.co/collections/x", "ep-foo"])
func rejectsBadRefs(raw: String) {
  #expect(EpisodeRef.parse(raw) == nil)
}

@Test func pathComponentPrefersSlug() {
  #expect(EpisodeRef.parse("381")?.pathComponent == "381")
  #expect(EpisodeRef.parse("ep381-a-b")?.pathComponent == "ep381-a-b")
}

@Test func parsesSectionRefs() {
  #expect(SectionRef.parse("t349") == .timestamp(349))
  #expect(SectionRef.parse("5:49") == .timestamp(349))
  #expect(SectionRef.parse("1:02:03") == .timestamp(3723))
  #expect(SectionRef.parse("#introduction") == .slug("introduction"))
  #expect(SectionRef.parse("Introduction") == .slug("introduction"))
}
```

- [ ] **Step 2: Запустить — не компилируется**

Run: `swift test --filter EpisodeRefTests`
Expected: ошибка компиляции.

- [ ] **Step 3: Реализация**

```swift
import Foundation

public enum SectionRef: Equatable, Sendable {
  case timestamp(Int)
  case slug(String)

  public static func parse(_ raw: String) -> SectionRef? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("#") { text.removeFirst() }
    guard !text.isEmpty else { return nil }
    let looksLikeTime = text.hasPrefix("t") && Int(text.dropFirst()) != nil || text.contains(":") || Int(text) != nil
    if looksLikeTime, let seconds = Timecode.seconds(from: text) { return .timestamp(seconds) }
    return .slug(text.lowercased())
  }
}

public struct EpisodeRef: Equatable, Sendable {
  public var number: Int
  public var slug: String?
  public var section: SectionRef?

  public var pathComponent: String { slug ?? String(number) }

  public static func parse(_ raw: String) -> EpisodeRef? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    var section: SectionRef? = nil
    if let hash = text.firstIndex(of: "#") {
      section = SectionRef.parse(String(text[text.index(after: hash)...]))
      text = String(text[..<hash])
    }
    if let q = text.firstIndex(of: "?") { text = String(text[..<q]) }
    if let range = text.range(of: "/episodes/") { text = String(text[range.upperBound...]) }
    while text.hasSuffix("/") { text.removeLast() }
    text = text.lowercased()
    if let number = Int(text) { return EpisodeRef(number: number, slug: nil, section: section) }
    let pattern = /^ep(\d+)(?:-[a-z0-9-]*)?$/
    guard let match = text.wholeMatch(of: pattern), let number = Int(match.1) else { return nil }
    return EpisodeRef(number: number, slug: text, section: section)
  }
}
```

- [ ] **Step 4: Тесты проходят**

Run: `swift test --filter EpisodeRefTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PointFreeKit/Models/EpisodeRef.swift Tests/PointFreeKitTests/EpisodeRefTests.swift
git commit -m "feat: parse episode and section references"
```

---

### Task 4: HTTPClient, SessionStore и ошибки

**Files:**
- Create: `Sources/PointFreeKit/Client/HTTPClient.swift`
- Create: `Sources/PointFreeKit/Client/PointFreeError.swift`
- Create: `Sources/PointFreeKit/Session/Session.swift`
- Create: `Sources/PointFreeKit/Session/SessionStore.swift`
- Test: `Tests/PointFreeKitTests/SessionStoreTests.swift`

**Interfaces:**
- Produces: `HTTPResponse { statusCode: Int; body: Data; headers: [String: String] }`, `HTTPClient.fetch(URLRequest) async throws -> HTTPResponse` (dependency `\.httpClient`), `Session { cookie, expiresAt, savedAt }`, `SessionStore.load/save/clear` (dependency `\.sessionStore`), `SessionStore.file(in directory: URL)`, `PointFreeError`.

- [ ] **Step 1: Тест хранилища**

```swift
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
```

- [ ] **Step 2: Запустить — не компилируется**

Run: `swift test --filter SessionStoreTests`

- [ ] **Step 3: Реализация**

`Sources/PointFreeKit/Client/PointFreeError.swift`:
```swift
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
```

`Sources/PointFreeKit/Client/HTTPClient.swift`:
```swift
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
```

`Sources/PointFreeKit/Session/Session.swift`:
```swift
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
```

`Sources/PointFreeKit/Session/SessionStore.swift`:
```swift
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
```

- [ ] **Step 4: Тесты проходят**

Run: `swift test --filter SessionStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PointFreeKit/Client Sources/PointFreeKit/Session Tests/PointFreeKitTests/SessionStoreTests.swift
git commit -m "feat: HTTP client, session store and error type"
```

---

### Task 5: Кэш в памяти

**Files:**
- Create: `Sources/PointFreeKit/Cache/MemoryCache.swift`
- Test: `Tests/PointFreeKitTests/MemoryCacheTests.swift`

**Interfaces:**
- Produces: `actor MemoryCache<Value: Sendable>` с `init(ttl: TimeInterval, maxEntries: Int, now: @escaping @Sendable () -> Date)`, `func value(for key: String) -> Value?`, `func set(_ value: Value, for key: String)`, `func removeAll()`.

- [ ] **Step 1: Тест**

```swift
import Foundation
import Testing
@testable import PointFreeKit

@Test func cacheExpiresByTTLAndEvictsOldest() async {
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
```

- [ ] **Step 2: Запустить — не компилируется**

- [ ] **Step 3: Реализация**

```swift
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
```

- [ ] **Step 4: Тест проходит**, затем commit:

```bash
git add Sources/PointFreeKit/Cache Tests/PointFreeKitTests/MemoryCacheTests.swift
git commit -m "feat: in-memory TTL cache"
```

---

### Task 6: PointFreeClient (живой клиент сайта)

**Files:**
- Create: `Sources/PointFreeKit/Client/PointFreeClient.swift`
- Create: `Sources/PointFreeKit/Client/SearchQuery.swift`
- Test: `Tests/PointFreeKitTests/PointFreeClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `SessionStore`, `MemoryCache`, `PointFreeJSON`, `EpisodeSummary`, `EpisodeDetail`, `PointFreeError`.
- Produces: `SearchQuery { query, scope: Scope?, access: Access?, sort: Sort? }` с `url`, `PointFreeClient` (dependency `\.pointFreeClient`) с полями:
  - `episodes: () async throws -> [EpisodeSummary]`
  - `episode: (_ id: Int) async throws -> EpisodeDetail`
  - `episodePage: (_ pathComponent: String) async throws -> String`
  - `search: (_ query: SearchQuery) async throws -> String`
  - `collectionsPage: () async throws -> String`
  - `collectionPage: (_ slug: String) async throws -> String`
  - `sectionPage: (_ slug: String, _ section: String) async throws -> String`
  - `blogFeed: () async throws -> String` (Atom XML)
  - `validateSession: (_ cookie: String) async throws -> Bool`
  - `invalidateCache: () async -> Void`
  - `PointFreeClient.live(cache:)` и `PointFreeClient.baseURL`.

- [ ] **Step 1: Тесты**

```swift
import Dependencies
import Foundation
import Testing
@testable import PointFreeKit

private final class RequestLog: @unchecked Sendable { var requests: [URLRequest] = [] }

private func client(
  session: Session? = nil,
  log: RequestLog,
  respond: @escaping @Sendable (URLRequest) throws -> HTTPResponse
) -> PointFreeClient {
  withDependencies {
    $0.httpClient.fetch = { req in log.requests.append(req); return try respond(req) }
    $0.sessionStore.load = { session }
    $0.sessionStore.save = { _ in }
    $0.sessionStore.clear = { }
    $0.date.now = Date(timeIntervalSince1970: 1_000)
  } operation: {
    PointFreeClient.live(cache: MemoryCache(ttl: 60, maxEntries: 10, now: { Date(timeIntervalSince1970: 1_000) }))
  }
}

@Test func searchQueryEncodesSpecialCharacters() {
  let q = SearchQuery(query: "a & b + c #d", scope: .code, access: .free, sort: .newest)
  #expect(q.url.absoluteString == "https://www.pointfree.co/search?q=a%20%26%20b%20%2B%20c%20%23d&scope=code&access=free&sort=newest")
  #expect(SearchQuery(query: "x").url.absoluteString == "https://www.pointfree.co/search?q=x")
}

@Test func episodesDecodeAndAreCached() async throws {
  let log = RequestLog()
  let data = try fixture("episodes.json")
  let c = client(log: log) { _ in HTTPResponse(statusCode: 200, body: data) }
  let first = try await c.episodes()
  let second = try await c.episodes()
  #expect(first.count == 3 && second.count == 3)
  #expect(log.requests.count == 1)
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/api/episodes")
  #expect(log.requests[0].value(forHTTPHeaderField: "Cookie") == nil)
}

@Test func missingEpisodeIsNotFoundNotDecodingError() async throws {
  let log = RequestLog()
  let c = client(log: log) { _ in HTTPResponse(statusCode: 404, body: Data("<html>Page not found</html>".utf8)) }
  await #expect(throws: PointFreeError.notFound(URL(string: "https://www.pointfree.co/api/episodes/9999")!)) {
    _ = try await c.episode(9999)
  }
}

@Test func episodePageSendsCookieOnlyWhenSessionExists() async throws {
  let log = RequestLog()
  let session = Session(cookie: "COOKIE", expiresAt: Date(timeIntervalSince1970: 5_000), savedAt: Date(timeIntervalSince1970: 0))
  let c = client(session: session, log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<html></html>".utf8)) }
  _ = try await c.episodePage("ep381-x")
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/episodes/ep381-x")
  #expect(log.requests[0].value(forHTTPHeaderField: "Cookie") == "pf_session=COOKIE")

  let anon = client(log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<html></html>".utf8)) }
  _ = try await anon.episodePage("ep381-x")
  #expect(log.requests[1].value(forHTTPHeaderField: "Cookie") == nil)
}

@Test func expiredSessionIsNotSent() async throws {
  let log = RequestLog()
  let session = Session(cookie: "OLD", expiresAt: Date(timeIntervalSince1970: 500), savedAt: Date(timeIntervalSince1970: 0))
  let c = client(session: session, log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<html></html>".utf8)) }
  _ = try await c.episodePage("1")
  #expect(log.requests[0].value(forHTTPHeaderField: "Cookie") == nil)
}

@Test func validateSessionTreatsRedirectAsInvalid() async throws {
  let log = RequestLog()
  let c = client(log: log) { req in
    HTTPResponse(statusCode: req.value(forHTTPHeaderField: "Cookie") == "pf_session=GOOD" ? 200 : 302, body: Data())
  }
  #expect(try await c.validateSession("GOOD") == true)
  #expect(try await c.validateSession("BAD") == false)
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/account")
}

@Test func blogFeedIsFetchedFromAtomURL() async throws {
  let log = RequestLog()
  let c = client(log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<feed/>".utf8)) }
  #expect(try await c.blogFeed() == "<feed/>")
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/blog/feed/atom.xml")
}

@Test func serverErrorsSurfaceAsHttpStatus() async throws {
  let log = RequestLog()
  let c = client(log: log) { _ in HTTPResponse(statusCode: 503, body: Data()) }
  await #expect(throws: PointFreeError.httpStatus(503, URL(string: "https://www.pointfree.co/collections")!)) {
    _ = try await c.collectionsPage()
  }
}
```

- [ ] **Step 2: Запустить — не компилируется**

- [ ] **Step 3: Реализация**

`Sources/PointFreeKit/Client/SearchQuery.swift`:
```swift
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
    var components = URLComponents(url: PointFreeClient.baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
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
    return components.url!
  }

  public var cacheKey: String { url.absoluteString }
}
```

`Sources/PointFreeKit/Client/PointFreeClient.swift`:
```swift
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct PointFreeClient: Sendable {
  public var episodes: @Sendable () async throws -> [EpisodeSummary]
  public var episode: @Sendable (_ id: Int) async throws -> EpisodeDetail
  public var episodePage: @Sendable (_ pathComponent: String) async throws -> String
  public var search: @Sendable (_ query: SearchQuery) async throws -> String
  public var collectionsPage: @Sendable () async throws -> String
  public var collectionPage: @Sendable (_ slug: String) async throws -> String
  public var sectionPage: @Sendable (_ slug: String, _ section: String) async throws -> String
  public var blogFeed: @Sendable () async throws -> String
  public var validateSession: @Sendable (_ cookie: String) async throws -> Bool
  public var invalidateCache: @Sendable () async -> Void
}

extension PointFreeClient {
  public static let baseURL = URL(string: "https://www.pointfree.co")!
  public static let cookieName = "pf_session"

  public static func live(cache: MemoryCache<String>) -> PointFreeClient {
    // Зависимости захватываются в момент создания клиента и биндятся в let,
    // чтобы @Sendable-замыкания не захватывали var.
    @Dependency(\.httpClient) var httpDependency
    @Dependency(\.sessionStore) var sessionStoreDependency
    @Dependency(\.date) var dateDependency
    let http = httpDependency
    let sessionStore = sessionStoreDependency
    let date = dateDependency

    @Sendable func currentCookie() -> String? {
      guard let session = try? sessionStore.load(), !session.isExpired(now: date.now) else { return nil }
      return session.cookie
    }

    /// GET с cookie (если есть), 404 -> notFound, 3xx/4xx/5xx -> httpStatus.
    @Sendable func get(_ path: String, query: [URLQueryItem] = [], url overrideURL: URL? = nil, cookie: String?) async throws -> HTTPResponse {
      let url: URL
      if let overrideURL { url = overrideURL } else {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        url = components.url!
      }
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
      if let cookie, url.host == baseURL.host {
        request.setValue("\(cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
      }
      let response = try await http.fetch(request)
      switch response.statusCode {
      case 200: return response
      case 404: throw PointFreeError.notFound(url)
      default: throw PointFreeError.httpStatus(response.statusCode, url)
      }
    }

    @Sendable func cachedHTML(key: String, _ load: @Sendable () async throws -> HTTPResponse) async throws -> String {
      if let hit = await cache.value(for: key) { return hit }
      let html = String(decoding: try await load().body, as: UTF8.self)
      await cache.set(html, for: key)
      return html
    }

    return PointFreeClient(
      episodes: {
        let key = "api/episodes"
        if let hit = await cache.value(for: key), let data = hit.data(using: .utf8) {
          return try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: data)
        }
        let response = try await get("api/episodes", cookie: nil)
        do {
          let episodes = try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: response.body)
          await cache.set(String(decoding: response.body, as: UTF8.self), for: key)
          return episodes
        } catch {
          throw PointFreeError.decoding("episodes: \(error)")
        }
      },
      episode: { id in
        let response = try await get("api/episodes/\(id)", cookie: nil)
        do { return try PointFreeJSON.decoder.decode(EpisodeDetail.self, from: response.body) }
        catch { throw PointFreeError.decoding("episode \(id): \(error)") }
      },
      episodePage: { pathComponent in
        let cookie = currentCookie()
        let key = "episode/\(pathComponent)/\(cookie == nil ? "anon" : "auth")"
        return try await cachedHTML(key: key) { try await get("episodes/\(pathComponent)", cookie: cookie) }
      },
      search: { query in
        try await cachedHTML(key: "search/\(query.cacheKey)") { try await get("", url: query.url, cookie: nil) }
      },
      collectionsPage: {
        try await cachedHTML(key: "collections") { try await get("collections", cookie: nil) }
      },
      collectionPage: { slug in
        try await cachedHTML(key: "collections/\(slug)") { try await get("collections/\(slug)", cookie: nil) }
      },
      sectionPage: { slug, section in
        try await cachedHTML(key: "collections/\(slug)/\(section)") { try await get("collections/\(slug)/\(section)", cookie: nil) }
      },
      blogFeed: {
        try await cachedHTML(key: "blog/feed/atom.xml") { try await get("blog/feed/atom.xml", cookie: nil) }
      },
      validateSession: { cookie in
        var request = URLRequest(url: baseURL.appendingPathComponent("account"))
        request.setValue("\(cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
        let response = try await http.fetch(request)
        return response.statusCode == 200
      },
      invalidateCache: { await cache.removeAll() }
    )
  }
}

extension PointFreeClient: DependencyKey {
  public static let liveValue = PointFreeClient.live(cache: MemoryCache(ttl: 60 * 60, maxEntries: 50))
}

extension DependencyValues {
  public var pointFreeClient: PointFreeClient {
    get { self[PointFreeClient.self] }
    set { self[PointFreeClient.self] = newValue }
  }
}
```

- [ ] **Step 4: Тесты проходят**

Run: `swift test --filter PointFreeClientTests`
Expected: 8 тестов PASS. Если `withDependencies` не подхватывает `$0.date.now` в `live`, вызывать `live` внутри `operation` (как в helper `client`) — зависимости захватываются при создании.

- [ ] **Step 5: Commit**

```bash
git add Sources/PointFreeKit/Client Tests/PointFreeKitTests/PointFreeClientTests.swift
git commit -m "feat: PointFreeClient with caching and session cookie"
```

---

### Task 7: Парсер страницы эпизода (транскрипт)

**Files:**
- Create: `Sources/PointFreeKit/Models/Transcript.swift`
- Create: `Sources/PointFreeKit/Parsing/InlineMarkdown.swift`
- Create: `Sources/PointFreeKit/Parsing/EpisodePageParser.swift`
- Create: `Tests/PointFreeKitTests/Fixtures/episode-free.html`
- Create: `Tests/PointFreeKitTests/Fixtures/episode-locked.html`
- Test: `Tests/PointFreeKitTests/EpisodePageParserTests.swift`

**Interfaces:**
- Produces: `Transcript { chapters: [Chapter] }`, `Chapter { slug, title, startTimestamp: Int?, blocks: [Block] }`, `Block { case timestamp(Int), speaker(String), paragraph(String), code(String), listItem(String), quote(String), heading(String) }`, `EpisodePage { transcript: Transcript; tocChapterCount: Int; isTruncated: Bool }`, `EpisodePageParser.parse(html: String, url: URL?) throws -> EpisodePage`, `InlineMarkdown.render(_ element: Element) throws -> String`, `Transcript.hasBody`.

Реальная разметка (классы хэшированы, опираемся на теги и атрибуты):
```html
<article><pf-markdown><pf-vstack>
  <a id="introduction"></a><div><h4>Introduction<a href="#introduction"><svg/></a></h4></div>
  <div><strong>Brandon</strong><div>…</div></div>
  <div><div id="t68"><a data-timestamp="68" href="#t68">1:08</a></div></div>
  <p>Text with <code>incr</code> and <a href="/x">link</a>.</p>
  <pre><code>extension Int {
  func incr() -> Int { self + 1 }
}
</code></pre>
  <ol><li>Item</li></ol>
</pf-vstack></pf-markdown></article>
```
Оглавление (TOC) вне `article`: `<li><pf-hstack><a href="#introduction">…</a><a data-timestamp="68" href="#t68">1:08</a></pf-hstack></li>` — ссылки не прямые дети `li`, поэтому TOC считается по `a[data-timestamp]` вне `article` (уникальные href). У платного эпизода без сессии `article` содержит только первые 1–2 главы (превью), а в TOC глав больше: `tocChapterCount > transcript.chapters.count` означает «обрезано».

- [ ] **Step 1: Фикстуры**

`Tests/PointFreeKitTests/Fixtures/episode-free.html`:
```html
<!doctype html><html><head><title>Episode #1: Functions</title></head><body>
<nav><ul>
  <li><a href="#introduction">Introduction</a><a data-timestamp="5" href="#t5">0:05</a></li>
  <li><a href="#composition">Composition</a><a data-timestamp="141" href="#t141">2:21</a></li>
</ul></nav>
<article><pf-markdown><pf-vstack>
  <a id="introduction"></a><div><h4>Introduction<a href="#introduction"><svg></svg></a></h4></div>
  <div><strong>Brandon</strong><div><div id="t5"><a data-timestamp="5" href="#t5">0:05</a></div></div></div>
  <p>Placeholder intro with <code>incr</code> and a <a href="/episodes/ep2-side-effects">link</a>, plus <em>emphasis</em> and <strong>bold</strong>.</p>
  <pre><code>func incr(_ x: Int) -&gt; Int {
  return x + 1  // a &amp; b &lt; c
}
</code></pre>
  <div><div id="t68"><a data-timestamp="68" href="#t68">1:08</a></div></div>
  <p>Second paragraph.</p>
  <ol><li>First item with <code>code</code></li><li>Second item</li></ol>
  <a id="composition"></a><div><h4>Composition<a href="#composition"><svg></svg></a></h4></div>
  <div><strong>Stephen</strong><div><div id="t141"><a data-timestamp="141" href="#t141">2:21</a></div></div></div>
  <p>Composition paragraph.</p>
  <pre><code><span class="k">let</span> f = incr &gt;&gt;&gt; square</code></pre>
  <blockquote><p>Quoted <code>note</code>.</p></blockquote>
  <h3>Inner heading</h3>
  <p>After heading.</p>
</pf-vstack></pf-markdown></article>
<footer><h4>Join Point-Free</h4><p>Footer text must not appear.</p></footer>
</body></html>
```

`Tests/PointFreeKitTests/Fixtures/episode-locked.html`:
```html
<!doctype html><html><head><title>Episode #381</title></head><body>
<nav><ul>
  <li><a href="#introduction">Introduction</a><a data-timestamp="5" href="#t5">0:05</a></li>
  <li><a href="#the-wrong-way">The wrong way</a><a data-timestamp="120" href="#t120">2:00</a></li>
  <li><a href="#a-better-way">A better way</a><a data-timestamp="349" href="#t349">5:49</a></li>
  <li><a href="#next-time">Next time</a><a data-timestamp="902" href="#t902">15:02</a></li>
</ul></nav>
<article><pf-markdown><pf-vstack>
  <a id="introduction"></a><div><h4>Introduction<a href="#introduction"><svg></svg></a></h4></div>
  <div><strong>Brandon</strong><div><div id="t5"><a data-timestamp="5" href="#t5">0:05</a></div></div></div>
  <p>Preview paragraph one.</p>
  <p>Preview paragraph two.</p>
  <a id="the-wrong-way"></a><div><h4>The wrong way<a href="#the-wrong-way"><svg></svg></a></h4></div>
</pf-vstack></pf-markdown></article>
</body></html>
```

- [ ] **Step 2: Тесты**

```swift
import Foundation
import Testing
@testable import PointFreeKit

@Test func parsesFreeEpisodeTranscript() throws {
  let page = try EpisodePageParser.parse(html: fixtureString("episode-free.html"), url: nil)
  #expect(page.tocChapterCount == 2)
  #expect(!page.isTruncated)
  let t = page.transcript
  #expect(t.chapters.map(\.title) == ["Introduction", "Composition"])
  #expect(t.chapters.map(\.slug) == ["introduction", "composition"])
  #expect(t.chapters[0].startTimestamp == 5)
  #expect(t.chapters[1].startTimestamp == 141)

  let intro = t.chapters[0].blocks
  #expect(intro[0] == .speaker("Brandon"))
  #expect(intro[1] == .timestamp(5))
  #expect(intro[2] == .paragraph("Placeholder intro with `incr` and a [link](https://www.pointfree.co/episodes/ep2-side-effects), plus *emphasis* and **bold**."))
  #expect(intro[3] == .code("func incr(_ x: Int) -> Int {\n  return x + 1  // a & b < c\n}\n"))
  #expect(intro[4] == .timestamp(68))
  #expect(intro[5] == .paragraph("Second paragraph."))
  #expect(intro[6] == .listItem("First item with `code`"))
  #expect(intro[7] == .listItem("Second item"))
  #expect(intro.count == 8)

  let comp = t.chapters[1].blocks
  #expect(comp.contains(.code("let f = incr >>> square")))
  #expect(comp.contains(.quote("Quoted `note`.")))
  #expect(comp.contains(.heading("Inner heading")))
  #expect(comp.contains(.paragraph("After heading.")))
  #expect(!comp.contains(.paragraph("Quoted `note`.")))
  #expect(t.chapters.count == 2)  // h3 внутри статьи не открывает новую главу
  #expect(t.hasBody)
  // Текст футера не попал в транскрипт
  #expect(!t.chapters.flatMap(\.blocks).contains(.paragraph("Footer text must not appear.")))
}

@Test func detectsTruncatedLockedEpisode() throws {
  let page = try EpisodePageParser.parse(html: fixtureString("episode-locked.html"), url: nil)
  #expect(page.tocChapterCount == 4)
  #expect(page.transcript.chapters.count == 2)
  #expect(page.isTruncated)
}

@Test func missingArticleIsStructureChange() {
  #expect(throws: PointFreeError.structureChanged("article", nil)) {
    _ = try EpisodePageParser.parse(html: "<html><body><p>nope</p></body></html>", url: nil)
  }
}
```

- [ ] **Step 3: Запустить — не компилируется**

- [ ] **Step 4: Реализация**

`Sources/PointFreeKit/Models/Transcript.swift`:
```swift
public struct Transcript: Equatable, Sendable {
  public struct Chapter: Equatable, Sendable {
    public var slug: String
    public var title: String
    public var startTimestamp: Int?
    public var blocks: [Block]
    public init(slug: String, title: String, startTimestamp: Int? = nil, blocks: [Block] = []) {
      self.slug = slug; self.title = title; self.startTimestamp = startTimestamp; self.blocks = blocks
    }
  }

  public enum Block: Equatable, Sendable {
    case timestamp(Int)
    case speaker(String)
    case paragraph(String)
    case code(String)
    case listItem(String)
    case quote(String)
    case heading(String)
  }

  public var chapters: [Chapter]
  public init(chapters: [Chapter]) { self.chapters = chapters }

  /// Есть ли содержательный текст (абзацы или код), а не только оглавление.
  public var hasBody: Bool {
    chapters.contains { chapter in
      chapter.blocks.contains { block in
        if case .paragraph = block { return true }
        if case .code = block { return true }
        return false
      }
    }
  }

  public func chapter(matching ref: SectionRef) -> Chapter? {
    switch ref {
    case .slug(let slug):
      if let exact = chapters.first(where: { $0.slug == slug }) { return exact }
      return chapters.first { $0.title.lowercased().contains(slug.replacingOccurrences(of: "-", with: " ")) }
    case .timestamp(let seconds):
      if let containing = chapters.first(where: { $0.blocks.contains(.timestamp(seconds)) }) { return containing }
      return chapters.last { ($0.startTimestamp ?? Int.max) <= seconds }
    }
  }
}
```

`Sources/PointFreeKit/Parsing/InlineMarkdown.swift`:
```swift
import Foundation
import SwiftSoup

public enum InlineMarkdown {
  /// Переводит inline-разметку элемента (code, a, em, strong, br) в markdown; остальные теги — их текст.
  public static func render(_ element: Element, baseURL: URL = PointFreeClient.baseURL) throws -> String {
    var out = ""
    for node in element.getChildNodes() {
      if let text = node as? TextNode {
        out += text.getWholeText()
      } else if let child = node as? Element {
        switch child.tagName() {
        case "code": out += "`" + (try child.text()) + "`"
        case "em", "i": out += "*" + (try render(child, baseURL: baseURL)) + "*"
        case "strong", "b": out += "**" + (try render(child, baseURL: baseURL)) + "**"
        case "br": out += "\n"
        case "a":
          let href = try child.attr("href")
          let label = try render(child, baseURL: baseURL)
          let absolute = URL(string: href, relativeTo: baseURL)?.absoluteString ?? href
          out += href.isEmpty ? label : "[\(label)](\(absolute))"
        case "svg", "img": break
        default: out += try render(child, baseURL: baseURL)
        }
      }
    }
    return out.replacingOccurrences(of: "\u{00A0}", with: " ")
      .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
      .joined(separator: " ")
      .replacingOccurrences(of: "  ", with: " ")
      .trimmingCharacters(in: .whitespaces)
  }

  /// Исходный текст без нормализации пробелов (для <pre>).
  public static func rawText(_ element: Element) -> String {
    var out = ""
    for node in element.getChildNodes() {
      if let text = node as? TextNode { out += text.getWholeText() }
      else if let child = node as? Element { out += rawText(child) }
    }
    return out
  }
}
```

`Sources/PointFreeKit/Parsing/EpisodePageParser.swift`:
```swift
import Foundation
import SwiftSoup

public struct EpisodePage: Equatable, Sendable {
  public var transcript: Transcript
  public var tocChapterCount: Int
  public var isTruncated: Bool { tocChapterCount > transcript.chapters.count }
}

public enum EpisodePageParser {
  public static func parse(html: String, url: URL?) throws -> EpisodePage {
    let doc = try SwiftSoup.parse(html)
    guard let article = try doc.select("article").first() else {
      throw PointFreeError.structureChanged("article", url)
    }

    // TOC: таймкоды глав вне article. На живой странице ссылки оглавления лежат
    // внутри pf-hstack внутри li, а боковые ссылки #references/#downloads без таймкода,
    // поэтому считаем именно a[data-timestamp] вне article (по уникальному href).
    let tocLinks = try doc.select("a[data-timestamp]")
      .filter { link in !(link.parents().contains { $0.tagName() == "article" }) }
    let tocChapterCount = Set(try tocLinks.map { try $0.attr("href") }).count

    var chapters: [Transcript.Chapter] = []
    var pendingSlug: String?

    func append(_ block: Transcript.Block) {
      // Тело транскрипта начинается с первого заголовка главы; блоки до него не учитываются.
      guard !chapters.isEmpty else { return }
      chapters[chapters.count - 1].blocks.append(block)
      if case .timestamp(let s) = block, chapters[chapters.count - 1].startTimestamp == nil {
        chapters[chapters.count - 1].startTimestamp = s
      }
    }

    func isInside(_ element: Element, _ tags: Set<String>) -> Bool {
      var current = element.parent()
      while let node = current, node.tagName() != "article" {
        if tags.contains(node.tagName()) { return true }
        current = node.parent()
      }
      return false
    }

    for node in try article.select("a[id], h4, h2, h3, h5, h6, a[data-timestamp], strong, p, pre, li, blockquote") {
      switch node.tagName() {
      case "a" where node.hasAttr("data-timestamp"):
        if let seconds = Int(try node.attr("data-timestamp")) { append(.timestamp(seconds)) }
      case "a":
        let id = try node.attr("id")
        if !id.isEmpty { pendingSlug = id }
      case "h4":
        let title = node.ownText().trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { continue }
        chapters.append(.init(slug: pendingSlug ?? slugify(title), title: title))
        pendingSlug = nil
      case "h2", "h3", "h5", "h6":
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { append(.heading(text)) }
      case "blockquote":
        let text = try node.select("p").map { try InlineMarkdown.render($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        let quote = try (text.isEmpty ? InlineMarkdown.render(node) : text)
        append(.quote(quote))
      case "strong":
        guard !isInside(node, ["p", "li", "h4", "blockquote"]) else { continue }
        let name = try node.text().trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { append(.speaker(name)) }
      case "p":
        guard !isInside(node, ["li", "blockquote"]) else { continue }
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { append(.paragraph(text)) }
      case "pre":
        let code = try node.select("code").first() ?? node
        var text = InlineMarkdown.rawText(code)
        if !text.hasSuffix("\n") && text.contains("\n") { text += "\n" }
        append(.code(text))
      case "li":
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { append(.listItem(text)) }
      default: break
      }
    }

    return EpisodePage(transcript: Transcript(chapters: chapters), tocChapterCount: tocChapterCount)
  }

  static func slugify(_ title: String) -> String {
    title.lowercased()
      .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
      .joined()
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
  }
}
```

- [ ] **Step 5: Тесты проходят**

Run: `swift test --filter EpisodePageParserTests`
Expected: 3 теста PASS. Если `.code` для второго блока содержит лишний `\n` в конце — ожидание в тесте `"let f = incr >>> square"` без переноса верное: перенос добавляется только когда в коде уже есть строки.

- [ ] **Step 6: Проверка на живой странице (вручную, не коммитить)**

```bash
mkdir -p Tests/live
curl -sS https://www.pointfree.co/episodes/ep1-functions -o Tests/live/ep1.html
```
Временный тест (не коммитить) или `swift run` с отладочной печатью: распарсить `Tests/live/ep1.html`, убедиться, что глав 7, блоков `code` 43, `isTruncated == false`. Затем удалить временный код.

- [ ] **Step 7: Commit**

```bash
git add Sources/PointFreeKit/Models/Transcript.swift Sources/PointFreeKit/Parsing Tests/PointFreeKitTests/Fixtures/episode-*.html Tests/PointFreeKitTests/EpisodePageParserTests.swift
git commit -m "feat: parse episode page transcript into chapters and blocks"
```

---

### Task 8: Парсер страницы поиска

**Files:**
- Create: `Sources/PointFreeKit/Models/SearchResult.swift`
- Create: `Sources/PointFreeKit/Parsing/SearchPageParser.swift`
- Create: `Tests/PointFreeKitTests/Fixtures/search.html`
- Test: `Tests/PointFreeKitTests/SearchPageParserTests.swift`

**Interfaces:**
- Produces: `SearchResult { slug, number: Int?, title, snippet: String?, hits: [Hit] }`, `SearchResult.Hit { title, timestamp: Int }`, `SearchPage { total: Int?; results: [SearchResult] }`, `SearchPageParser.parse(html:url:) throws -> SearchPage`.

Сайт показывает не больше ~50 карточек и не имеет пагинации, но пишет строку «80 videos match Sendable». Её число — `total`; рендер сообщает «showing N of total».

Реальная разметка карточки: `<h4><a href="/episodes/ep381-designing-for-isolation-naively">Designing for Isolation: Naively</a></h4>`, затем `<p>… <mark>Sendable</mark> …</p>`, затем несколько `<a href="/episodes/ep381-…#t349">Remaining non-Sendable a bit longer… (5:49)</a>`. Общий контейнер карточки — ближайший предок `h4`, внутри которого ровно одна ссылка на эпизод без `#`.

- [ ] **Step 1: Фикстура `search.html`**

```html
<!doctype html><html><body>
<h1>Search: Sendable</h1>
<p>80 videos match Sendable</p>
<div class="results">
  <div class="card">
    <h4><a href="/episodes/ep381-designing-for-isolation-naively">Designing for Isolation: Naively</a></h4>
    <div><p><span>… </span><code><mark>Sendable</mark></code>. Snippet text<span> …</span></p></div>
    <div><a href="/episodes/ep381-designing-for-isolation-naively#t349">Remaining non-Sendable a bit longer… (5:49)</a></div>
    <div><a href="/episodes/ep381-designing-for-isolation-naively#t902">Next time: Nonisolated Core (15:02)</a></div>
  </div>
  <div class="card">
    <h4><a href="/episodes/ep193-concurrency-s-future-sendable-and-actors">Concurrency's Future: <mark>Sendable</mark> and Actors</a></h4>
    <div><a href="/episodes/ep193-concurrency-s-future-sendable-and-actors#t688">Sendable (11:28)</a></div>
  </div>
</div>
<footer><a href="/episodes">All videos</a></footer>
</body></html>
```

- [ ] **Step 2: Тесты**

```swift
import Testing
@testable import PointFreeKit

@Test func parsesSearchCards() throws {
  let page = try SearchPageParser.parse(html: fixtureString("search.html"), url: nil)
  #expect(page.total == 80)
  let results = page.results
  #expect(results.count == 2)
  #expect(results[0].slug == "ep381-designing-for-isolation-naively")
  #expect(results[0].number == 381)
  #expect(results[0].title == "Designing for Isolation: Naively")
  #expect(results[0].snippet == "… Sendable. Snippet text …")
  #expect(results[0].hits == [
    .init(title: "Remaining non-Sendable a bit longer…", timestamp: 349),
    .init(title: "Next time: Nonisolated Core", timestamp: 902),
  ])
  #expect(results[1].title == "Concurrency's Future: Sendable and Actors")
  #expect(results[1].snippet == nil)
  #expect(results[1].hits == [.init(title: "Sendable", timestamp: 688)])
}

@Test func emptySearchGivesNoResults() throws {
  let page = try SearchPageParser.parse(html: "<html><body><h1>Search</h1><p>No results</p></body></html>", url: nil)
  #expect(page.results.isEmpty)
  #expect(page.total == nil)
}

@Test func matchesWithoutCardsIsStructureChange() {
  #expect(throws: PointFreeError.structureChanged("search result cards", nil)) {
    _ = try SearchPageParser.parse(html: "<html><body><p>12 videos match x</p><div>new markup</div></body></html>", url: nil)
  }
}
```

- [ ] **Step 3: Запустить — не компилируется**

- [ ] **Step 4: Реализация**

`Sources/PointFreeKit/Models/SearchResult.swift`:
```swift
public struct SearchResult: Equatable, Sendable {
  public struct Hit: Equatable, Sendable {
    public var title: String
    public var timestamp: Int
    public init(title: String, timestamp: Int) { self.title = title; self.timestamp = timestamp }
  }
  public var slug: String
  public var number: Int?
  public var title: String
  public var snippet: String?
  public var hits: [Hit]
}

public struct SearchPage: Equatable, Sendable {
  public var total: Int?
  public var results: [SearchResult]
}
```

`Sources/PointFreeKit/Parsing/SearchPageParser.swift`:
```swift
import Foundation
import SwiftSoup

public enum SearchPageParser {
  public static func parse(html: String, url: URL?) throws -> SearchPage {
    let doc = try SwiftSoup.parse(html)
    let bodyText = try doc.body()?.text() ?? ""
    let total = bodyText.firstMatch(of: /(\d+) videos? match/).flatMap { Int($0.1) }
    var results: [SearchResult] = []
    for titleLink in try doc.select("h4 > a[href^=/episodes/]") {
      let href = try titleLink.attr("href")
      let slug = String(href.dropFirst("/episodes/".count)).split(separator: "#")[0].description
      let title = try titleLink.text()
      let card = try cardContainer(for: titleLink) ?? titleLink
      let snippet = try card.select("p:has(mark)").first().map { try $0.text() }
      var hits: [SearchResult.Hit] = []
      for link in try card.select("a[href*=#t]") {
        let hitHref = try link.attr("href")
        guard let fragment = hitHref.split(separator: "#").last, let seconds = Int(fragment.dropFirst()) else { continue }
        let text = try link.text()
        hits.append(.init(title: stripTimeSuffix(text), timestamp: seconds))
      }
      results.append(SearchResult(slug: slug, number: EpisodeRef.parse(slug)?.number, title: title, snippet: snippet, hits: hits))
    }
    if results.isEmpty, let total, total > 0 {
      throw PointFreeError.structureChanged("search result cards", url)
    }
    return SearchPage(total: total, results: results)
  }

  /// Ближайший предок, в котором ровно одна ссылка на эпизод без "#".
  static func cardContainer(for link: Element) throws -> Element? {
    var best: Element? = nil
    var current = link.parent()
    while let node = current {
      let episodeLinks = try node.select("a[href^=/episodes/]").filter { !(try $0.attr("href")).contains("#") }
      if episodeLinks.count > 1 { break }
      best = node
      current = node.parent()
    }
    return best
  }

  /// "Title (5:49)" -> "Title"
  static func stripTimeSuffix(_ text: String) -> String {
    guard let open = text.lastIndex(of: "("), text.hasSuffix(")") else { return text }
    return String(text[..<open]).trimmingCharacters(in: .whitespaces)
  }
}
```

- [ ] **Step 5: Тесты проходят**, затем commit:

```bash
git add Sources/PointFreeKit/Models/SearchResult.swift Sources/PointFreeKit/Parsing/SearchPageParser.swift Tests/PointFreeKitTests/Fixtures/search.html Tests/PointFreeKitTests/SearchPageParserTests.swift
git commit -m "feat: parse search results page"
```

---

### Task 9: Парсеры коллекций

**Files:**
- Create: `Sources/PointFreeKit/Models/Collection.swift`
- Create: `Sources/PointFreeKit/Parsing/CollectionsParser.swift`
- Create: `Tests/PointFreeKitTests/Fixtures/collections.html`, `collection.html`, `section.html`
- Test: `Tests/PointFreeKitTests/CollectionsParserTests.swift`

**Interfaces:**
- Produces: `CollectionSummary { slug, title, description: String? }`, `CollectionSection { slug, title }`, `SectionEpisode { number: Int, slug, title, duration: String? }`, `SectionGroup { heading, episodes: [SectionEpisode] }`, `CollectionsParser.parseIndex(html:) throws -> [CollectionSummary]`, `parseCollection(html:slug:) throws -> (title: String, sections: [CollectionSection])`, `parseSection(html:) throws -> (title: String, groups: [SectionGroup])`.

Реальная разметка. Индекс: `<a href="/collections/composable-architecture"><svg/><div><h4>Composable Architecture</h4><div>Collection</div></div></a><pf-vstack>…<p>описание</p>…</pf-vstack>`. Коллекция: `<h2>Sections</h2>` и ссылки `<a href="https://www.pointfree.co/collections/composable-architecture/testing"><div><div>Testing</div><div><img alt></div></div></a>`. Секция: `<h2>Core lessons</h2>` затем `<a href="/collections/composable-architecture/testing/ep82-testable-state-management-reducers"><img><div>Testable State Management: Reducers</div><div>35&nbsp;min</div></a>`, дальше `<h2>Related content</h2>` с `<a href="/episodes/ep86-swiftui-snapshot-testing">…`.

- [ ] **Step 1: Фикстуры**

`collections.html`:
```html
<html><body>
<a href="/collections">All collections</a>
<div>
  <a href="/collections/composable-architecture"><svg></svg><div><h4>Composable Architecture</h4><div>Collection</div></div></a>
  <pf-vstack><pf-vstack><div><pf-markdown><p>TCA description.</p></pf-markdown></div></pf-vstack></pf-vstack>
</div>
<div>
  <a href="/collections/concurrency"><svg></svg><div><h4>Concurrency</h4><div>Collection</div></div></a>
  <pf-vstack><p>Concurrency description.</p></pf-vstack>
</div>
</body></html>
```

`collection.html`:
```html
<html><body>
<h1>Composable Architecture</h1>
<div><h2>Sections</h2></div>
<div><a href="https://www.pointfree.co/collections/composable-architecture/swiftui-and-state-management"><div><div>SwiftUI and State Management</div><div><img alt></div></div></a></div>
<div><a href="https://www.pointfree.co/collections/composable-architecture/testing"><div><div>Testing</div><div><img alt></div></div></a></div>
</body></html>
```

`section.html`:
```html
<html><body>
<h1>Testing</h1>
<div><h2>Core lessons</h2>
  <div><a href="/collections/composable-architecture/testing/ep82-testable-state-management-reducers"><img alt><div>Testable State Management: Reducers</div><div>35&nbsp;min</div></a></div>
  <div><a href="/collections/composable-architecture/testing/ep83-testable-state-management-effects"><img alt><div>Testable State Management: Effects</div><div>41&nbsp;min</div></a></div>
</div>
<div><h2>Related content</h2>
  <div><a href="/episodes/ep86-swiftui-snapshot-testing"><img alt><div>SwiftUI Snapshot Testing</div><div>28&nbsp;min</div></a></div>
</div>
<div><h2>Where to go from here</h2></div>
</body></html>
```

- [ ] **Step 2: Тесты**

```swift
import Testing
@testable import PointFreeKit

@Test func parsesCollectionsIndex() throws {
  let list = try CollectionsParser.parseIndex(html: fixtureString("collections.html"))
  #expect(list == [
    .init(slug: "composable-architecture", title: "Composable Architecture", description: "TCA description."),
    .init(slug: "concurrency", title: "Concurrency", description: "Concurrency description."),
  ])
}

@Test func emptyCollectionsIndexIsStructureChange() {
  #expect(throws: PointFreeError.self) {
    _ = try CollectionsParser.parseIndex(html: "<html><body><p>nothing</p></body></html>")
  }
}

@Test func parsesCollectionSections() throws {
  let c = try CollectionsParser.parseCollection(html: fixtureString("collection.html"), slug: "composable-architecture")
  #expect(c.title == "Composable Architecture")
  #expect(c.sections == [
    .init(slug: "swiftui-and-state-management", title: "SwiftUI and State Management"),
    .init(slug: "testing", title: "Testing"),
  ])
}

@Test func parsesSectionEpisodesGroupedByHeading() throws {
  let s = try CollectionsParser.parseSection(html: fixtureString("section.html"))
  #expect(s.title == "Testing")
  #expect(s.groups.map(\.heading) == ["Core lessons", "Related content"])
  #expect(s.groups[0].episodes == [
    .init(number: 82, slug: "ep82-testable-state-management-reducers", title: "Testable State Management: Reducers", duration: "35 min"),
    .init(number: 83, slug: "ep83-testable-state-management-effects", title: "Testable State Management: Effects", duration: "41 min"),
  ])
  #expect(s.groups[1].episodes == [
    .init(number: 86, slug: "ep86-swiftui-snapshot-testing", title: "SwiftUI Snapshot Testing", duration: "28 min"),
  ])
}
```

- [ ] **Step 3: Запустить — не компилируется**

- [ ] **Step 4: Реализация**

`Sources/PointFreeKit/Models/Collection.swift`:
```swift
public struct CollectionSummary: Equatable, Sendable {
  public var slug: String, title: String, description: String?
  public init(slug: String, title: String, description: String?) { self.slug = slug; self.title = title; self.description = description }
}
public struct CollectionSection: Equatable, Sendable {
  public var slug: String, title: String
  public init(slug: String, title: String) { self.slug = slug; self.title = title }
}
public struct SectionEpisode: Equatable, Sendable {
  public var number: Int, slug: String, title: String, duration: String?
  public init(number: Int, slug: String, title: String, duration: String?) { self.number = number; self.slug = slug; self.title = title; self.duration = duration }
}
public struct SectionGroup: Equatable, Sendable {
  public var heading: String, episodes: [SectionEpisode]
  public init(heading: String, episodes: [SectionEpisode]) { self.heading = heading; self.episodes = episodes }
}
```

`Sources/PointFreeKit/Parsing/CollectionsParser.swift`:
```swift
import Foundation
import SwiftSoup

public enum CollectionsParser {
  public static func parseIndex(html: String) throws -> [CollectionSummary] {
    let doc = try SwiftSoup.parse(html)
    var result: [CollectionSummary] = []
    for link in try doc.select("a[href^=/collections/]:has(h4)") {
      let slug = String(try link.attr("href").dropFirst("/collections/".count)).split(separator: "/")[0].description
      let title = try link.select("h4").first()?.text() ?? ""
      let description = try link.nextElementSibling()?.select("p").first()?.text()
      result.append(.init(slug: slug, title: title, description: description?.isEmpty == false ? description : nil))
    }
    guard !result.isEmpty else {
      throw PointFreeError.structureChanged("collections index", URL(string: "https://www.pointfree.co/collections"))
    }
    return result
  }

  public static func parseCollection(html: String, slug: String) throws -> (title: String, sections: [CollectionSection]) {
    let doc = try SwiftSoup.parse(html)
    let title = try doc.select("h1").first()?.text() ?? slug
    var sections: [CollectionSection] = []
    for link in try doc.select("a[href*=/collections/\(slug)/]") {
      let href = try link.attr("href")
      guard let sectionSlug = href.split(separator: "/").last.map(String.init), !sectionSlug.isEmpty else { continue }
      let sectionTitle = try link.select("div > div").first()?.text() ?? (try link.text())
      sections.append(.init(slug: sectionSlug, title: sectionTitle))
    }
    return (title, sections)
  }

  public static func parseSection(html: String) throws -> (title: String, groups: [SectionGroup]) {
    let doc = try SwiftSoup.parse(html)
    let title = try doc.select("h1").first()?.text() ?? ""
    var groups: [SectionGroup] = []
    let episodePattern = /(?:\/episodes\/|\/collections\/[^\/]+\/[^\/]+\/)(ep(\d+)-[a-z0-9-]+)/
    for node in try doc.select("h2, a[href*=/ep]") {
      if node.tagName() == "h2" {
        groups.append(.init(heading: try node.text(), episodes: []))
        continue
      }
      guard let match = try node.attr("href").firstMatch(of: episodePattern), let number = Int(match.2) else { continue }
      let divs = try node.select("div")
      let episodeTitle = divs.first().map { (try? $0.text()) ?? "" } ?? (try node.text())
      let duration: String? = try (divs.count > 1 ? divs.get(1).text().replacingOccurrences(of: "\u{00A0}", with: " ") : nil)
      let episode = SectionEpisode(number: number, slug: String(match.1), title: episodeTitle, duration: duration)
      if groups.isEmpty { groups.append(.init(heading: "Episodes", episodes: [])) }
      groups[groups.count - 1].episodes.append(episode)
    }
    return (title, groups.filter { !$0.episodes.isEmpty })
  }
}
```

- [ ] **Step 5: Тесты проходят**, затем commit:

```bash
git add Sources/PointFreeKit/Models/Collection.swift Sources/PointFreeKit/Parsing/CollectionsParser.swift Tests/PointFreeKitTests/Fixtures/collection*.html Tests/PointFreeKitTests/Fixtures/section.html Tests/PointFreeKitTests/CollectionsParserTests.swift
git commit -m "feat: parse collections, sections and section episodes"
```

---

### Task 10: Рендер markdown

**Files:**
- Create: `Sources/PointFreeKit/Rendering/MarkdownRenderer.swift`
- Test: `Tests/PointFreeKitTests/MarkdownRendererTests.swift`

**Interfaces:**
- Consumes: все модели из Tasks 2, 7, 8, 9.
- Produces: `MarkdownRenderer.episode(detail: EpisodeDetail, transcript: Transcript, section: SectionRef?) throws(PointFreeError) -> String`, `MarkdownRenderer.search(query: SearchQuery, page: SearchPage, episodes: [Int: EpisodeSummary]) -> String`, `MarkdownRenderer.blogPost(_ post: BlogPost, blocks: [Transcript.Block]) -> String`, `MarkdownRenderer.blogList(_ posts: [BlogPost]) -> String`, `MarkdownRenderer.episodeList(_ episodes: [EpisodeSummary]) -> String`, `MarkdownRenderer.collections(_:) -> String`, `MarkdownRenderer.collection(title:slug:sections:) -> String`, `MarkdownRenderer.section(collectionSlug:sectionSlug:title:groups:) -> String`.

- [ ] **Step 1: Тесты**

```swift
import Foundation
import Testing
@testable import PointFreeKit

private func detail381() -> EpisodeDetail {
  EpisodeDetail(id: 381, sequence: 381, title: "Designing for Isolation: Naively", blurb: "Blurb 381", length: 1008,
                publishedAt: Date(timeIntervalSinceReferenceDate: 812246400), subscriberOnly: true, image: "",
                codeSampleDirectory: "0381-isolation-design-pt2",
                references: [Reference(title: "FCIS", link: "https://example.invalid/fcis", author: "Gary", blurb: nil, publishedAt: nil)])
}

private func transcript() -> Transcript {
  Transcript(chapters: [
    .init(slug: "introduction", title: "Introduction", startTimestamp: 5, blocks: [
      .speaker("Brandon"), .timestamp(5), .paragraph("Hello `x`."), .code("let a = 1\n"), .listItem("Item"),
    ]),
    .init(slug: "next-time", title: "Next time", startTimestamp: 902, blocks: [.timestamp(902), .paragraph("Bye."), .quote("Note."), .heading("Sub")]),
  ])
}

@Test func rendersFullEpisode() throws {
  let md = try MarkdownRenderer.episode(detail: detail381(), transcript: transcript(), section: nil)
  let expected = """
  # Episode #381: Designing for Isolation: Naively

  - Published: 2026-09-28
  - Duration: 16:48
  - Access: Members only
  - URL: https://www.pointfree.co/episodes/381
  - Code samples: https://github.com/pointfreeco/episode-code-samples/tree/main/0381-isolation-design-pt2

  > Blurb 381

  ## References

  - [FCIS](https://example.invalid/fcis) — Gary

  ## Introduction [0:05](https://www.pointfree.co/episodes/381#t5)

  **Brandon**

  [0:05](https://www.pointfree.co/episodes/381#t5)

  Hello `x`.

  ```swift
  let a = 1
  ```

  - Item

  ## Next time [15:02](https://www.pointfree.co/episodes/381#t902)

  [15:02](https://www.pointfree.co/episodes/381#t902)

  Bye.

  > Note.

  ### Sub


  """
  #expect(md == expected)
}

@Test func rendersOnlyRequestedSection() throws {
  let md = try MarkdownRenderer.episode(detail: detail381(), transcript: transcript(), section: .timestamp(902))
  #expect(md.contains("## Next time"))
  #expect(!md.contains("## Introduction"))
  #expect(md.contains("Showing section 2 of 2"))
}

@Test func unknownSectionListsAvailableChapters() {
  #expect(throws: PointFreeError.invalidArgument("Section \"nope\" not found. Available sections: introduction (0:05), next-time (15:02)")) {
    _ = try MarkdownRenderer.episode(detail: detail381(), transcript: transcript(), section: .slug("nope"))
  }
}

@Test func rendersSearchResults() {
  let results = [SearchResult(slug: "ep381-x", number: 381, title: "T", snippet: "… Sendable …",
                              hits: [.init(title: "Hit", timestamp: 349)])]
  let summary = EpisodeSummary(id: 381, sequence: 381, title: "T", blurb: "", length: 1008,
                               publishedAt: Date(timeIntervalSinceReferenceDate: 812246400), subscriberOnly: true, image: "")
  let md = MarkdownRenderer.search(query: SearchQuery(query: "Sendable", scope: .dialogue), page: SearchPage(total: 80, results: results), episodes: [381: summary])
  #expect(md.hasPrefix("# Search: Sendable (scope: dialogue)\n\nShowing 1 of 80 matching video(s). The site returns at most ~50; narrow with `scope` or `access` to see the rest.\n\n"))
  #expect(md.contains("## #381: T (Members only)\n"))
  #expect(md.contains("https://www.pointfree.co/episodes/ep381-x\n"))
  #expect(md.contains("> … Sendable …"))
  #expect(md.contains("- [Hit (5:49)](https://www.pointfree.co/episodes/ep381-x#t349)"))
}

@Test func rendersEmptySearch() {
  let md = MarkdownRenderer.search(query: SearchQuery(query: "zzz"), page: SearchPage(total: nil, results: []), episodes: [:])
  #expect(md.contains("No episodes matched"))
}

@Test func rendersCompleteSearchWithoutWarning() {
  let r = [SearchResult(slug: "ep1-x", number: 1, title: "T", snippet: nil, hits: [])]
  let md = MarkdownRenderer.search(query: SearchQuery(query: "q"), page: SearchPage(total: 1, results: r), episodes: [:])
  #expect(md.contains("1 matching video(s).\n"))
  #expect(!md.contains("narrow with"))
}

@Test func rendersBlogPostAndList() {
  let post = BlogPost(number: 228, slug: "228-lazystate-1-0-now-available-to-everyone", title: "LazyState 1.0",
                      url: URL(string: "https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone")!,
                      updated: Date(timeIntervalSince1970: 1_789_300_000), contentHTML: "")
  let md = MarkdownRenderer.blogPost(post, blocks: [.paragraph("Hi"), .code("let x = 1\n"), .heading("Why")])
  #expect(md.hasPrefix("# LazyState 1.0\n\n- Published: 2026-09-13\n- URL: https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone\n\nHi\n\n```swift\nlet x = 1\n```\n\n### Why\n"))
  let list = MarkdownRenderer.blogList([post])
  #expect(list.contains("- #228 LazyState 1.0 — 2026-09-13 · https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone"))
}

@Test func rendersEpisodeListAndCollections() {
  let e = EpisodeSummary(id: 1, sequence: 1, title: "Functions", blurb: "", length: 1219,
                         publishedAt: Date(timeIntervalSinceReferenceDate: 538899069), subscriberOnly: false, image: "")
  #expect(MarkdownRenderer.episodeList([e]).contains("- #1 Functions — 2018-01-29 · 20:19 · Free · https://www.pointfree.co/episodes/1"))
  let c = MarkdownRenderer.collections([.init(slug: "tca", title: "TCA", description: "Desc")])
  #expect(c.contains("- **TCA** (`tca`): Desc"))
  let s = MarkdownRenderer.section(collectionSlug: "tca", sectionSlug: "testing", title: "Testing",
                                   groups: [.init(heading: "Core lessons", episodes: [.init(number: 82, slug: "ep82-x", title: "X", duration: "35 min")])])
  #expect(s.contains("## Core lessons\n\n- #82 X (35 min) — https://www.pointfree.co/episodes/ep82-x"))
}
```

- [ ] **Step 2: Запустить — не компилируется**

- [ ] **Step 3: Реализация**

```swift
import Foundation

public enum MarkdownRenderer {
  static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  static func date(_ d: Date) -> String { dateFormatter.string(from: d) }
  static func episodeURL(_ slugOrID: String) -> String { "https://www.pointfree.co/episodes/\(slugOrID)" }
  static func tsLink(_ base: String, _ seconds: Int) -> String { "[\(Timecode.label(seconds: seconds))](\(base)#t\(seconds))" }

  public static func episode(detail: EpisodeDetail, transcript: Transcript, section: SectionRef?) throws(PointFreeError) -> String {
    let base = detail.pageURL.absoluteString
    var out = "# Episode #\(detail.sequence): \(detail.title)\n\n"
    out += "- Published: \(date(detail.publishedAt))\n"
    out += "- Duration: \(detail.durationLabel)\n"
    out += "- Access: \(detail.accessLabel)\n"
    out += "- URL: \(base)\n"
    if let code = detail.codeSampleURL { out += "- Code samples: \(code.absoluteString)\n" }
    out += "\n> \(detail.blurb)\n\n"
    if !detail.references.isEmpty {
      out += "## References\n\n"
      for r in detail.references {
        let name = r.link.map { "[\(r.title)](\($0))" } ?? r.title
        out += "- \(name)" + (r.author.map { " — \($0)" } ?? "") + "\n"
      }
      out += "\n"
    }

    var chapters = transcript.chapters
    if let section {
      guard let index = chapters.firstIndex(where: { $0 == transcript.chapter(matching: section) }) else {
        let available = chapters.map { "\($0.slug) (\($0.startTimestamp.map { Timecode.label(seconds: $0) } ?? "-"))" }.joined(separator: ", ")
        throw .invalidArgument("Section \"\(sectionText(section))\" not found. Available sections: \(available)")
      }
      out += "_Showing section \(index + 1) of \(chapters.count). Omit `section` for the full transcript._\n\n"
      chapters = [chapters[index]]
    }

    for chapter in chapters {
      out += "## \(chapter.title)"
      if let ts = chapter.startTimestamp { out += " " + tsLink(base, ts) }
      out += "\n\n"
      for block in chapter.blocks {
        switch block {
        case .timestamp(let s): out += tsLink(base, s) + "\n\n"
        case .speaker(let name): out += "**\(name)**\n\n"
        case .paragraph(let text): out += text + "\n\n"
        case .code(let code): out += "```swift\n\(code.hasSuffix("\n") ? code : code + "\n")```\n\n"
        case .listItem(let text): out += "- \(text)\n"
        case .quote(let text): out += "> \(text)\n\n"
        case .heading(let text): out += "### \(text)\n\n"
        }
      }
      if case .listItem = chapter.blocks.last { out += "\n" }
    }
    return out
  }

  /// Общий рендер блоков без глав (блог).
  static func blocks(_ blocks: [Transcript.Block], base: String) -> String {
    var out = ""
    for block in blocks {
      switch block {
      case .timestamp(let s): out += tsLink(base, s) + "\n\n"
      case .speaker(let name): out += "**\(name)**\n\n"
      case .paragraph(let text): out += text + "\n\n"
      case .code(let code): out += "```swift\n\(code.hasSuffix("\n") ? code : code + "\n")```\n\n"
      case .listItem(let text): out += "- \(text)\n"
      case .quote(let text): out += "> \(text)\n\n"
      case .heading(let text): out += "### \(text)\n\n"
      }
    }
    if case .listItem = blocks.last { out += "\n" }
    return out
  }

  public static func blogPost(_ post: BlogPost, blocks: [Transcript.Block]) -> String {
    var out = "# \(post.title)\n\n- Published: \(date(post.updated))\n- URL: \(post.url.absoluteString)\n\n"
    out += Self.blocks(blocks, base: post.url.absoluteString)
    return out
  }

  public static func blogList(_ posts: [BlogPost]) -> String {
    var out = "# Point-Free Pointers blog (\(posts.count))\n\nCall `fetchBlogPost` with a post number, slug or URL to read one.\n\n"
    for p in posts { out += "- #\(p.number) \(p.title) — \(date(p.updated)) · \(p.url.absoluteString)\n" }
    return out
  }

  static func sectionText(_ ref: SectionRef) -> String {
    switch ref { case .slug(let s): return s; case .timestamp(let t): return "t\(t)" }
  }

  public static func search(query: SearchQuery, page: SearchPage, episodes: [Int: EpisodeSummary]) -> String {
    let results = page.results
    var out = "# Search: \(query.query)"
    if let scope = query.scope { out += " (scope: \(scope.rawValue))" }
    out += "\n\n"
    guard !results.isEmpty else {
      return out + "No episodes matched. Try a broader query, another `scope` (dialogue, code, titles), or drop `access`.\n"
    }
    if let total = page.total, total > results.count {
      out += "Showing \(results.count) of \(total) matching video(s). The site returns at most ~50; narrow with `scope` or `access` to see the rest.\n\n"
    } else {
      out += "\(results.count) matching video(s).\n\n"
    }
    for r in results {
      let summary = r.number.flatMap { episodes[$0] }
      let number = r.number.map { "#\($0): " } ?? ""
      let access = summary.map { " (\($0.accessLabel))" } ?? ""
      out += "## \(number)\(r.title)\(access)\n\(episodeURL(r.slug))\n\n"
      if let snippet = r.snippet { out += "> \(snippet)\n\n" }
      for hit in r.hits {
        out += "- [\(hit.title) (\(Timecode.label(seconds: hit.timestamp)))](\(episodeURL(r.slug))#t\(hit.timestamp))\n"
      }
      if !r.hits.isEmpty { out += "\n" }
    }
    return out
  }

  public static func episodeList(_ episodes: [EpisodeSummary]) -> String {
    var out = "# Point-Free episodes (\(episodes.count))\n\n"
    for e in episodes {
      out += "- #\(e.sequence) \(e.title) — \(date(e.publishedAt)) · \(e.durationLabel) · \(e.accessLabel) · \(episodeURL(String(e.id)))\n"
    }
    return out
  }

  public static func collections(_ list: [CollectionSummary]) -> String {
    var out = "# Point-Free collections (\(list.count))\n\nCall `fetchCollection` with `slug` to list its sections.\n\n"
    for c in list { out += "- **\(c.title)** (`\(c.slug)`)" + (c.description.map { ": \($0)" } ?? "") + "\n" }
    return out
  }

  public static func collection(title: String, slug: String, sections: [CollectionSection]) -> String {
    var out = "# Collection: \(title)\n\nhttps://www.pointfree.co/collections/\(slug)\n\nCall `fetchCollection` with `slug` and `section` to list episodes.\n\n"
    for s in sections { out += "- **\(s.title)** (`\(s.slug)`)\n" }
    return out
  }

  public static func section(collectionSlug: String, sectionSlug: String, title: String, groups: [SectionGroup]) -> String {
    var out = "# \(title)\n\nhttps://www.pointfree.co/collections/\(collectionSlug)/\(sectionSlug)\n\n"
    for g in groups {
      out += "## \(g.heading)\n\n"
      for e in g.episodes {
        out += "- #\(e.number) \(e.title)" + (e.duration.map { " (\($0))" } ?? "") + " — \(episodeURL(e.slug))\n"
      }
      out += "\n"
    }
    return out
  }
}
```

- [ ] **Step 4: Тесты проходят**

Run: `swift test --filter MarkdownRendererTests`
Expected: PASS. Дата `2026-09-28` соответствует `812246400` секунд от 2001-01-01 в UTC (проверено `date -r`), `2018-01-29` — `538899069`. Если тест на дату расходится на день, проверить `timeZone` форматтера, а не менять ожидание. Ожидаемая строка в `rendersFullEpisode` заканчивается двумя пустыми строками перед `"""`, потому что рендер завершает каждый блок `\n\n`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PointFreeKit/Rendering Tests/PointFreeKitTests/MarkdownRendererTests.swift
git commit -m "feat: markdown rendering for episodes, search, lists and collections"
```

---

### Task 11: Блог через Atom-фид

**Files:**
- Create: `Sources/PointFreeKit/Models/BlogPost.swift`
- Create: `Sources/PointFreeKit/Parsing/BlogFeedParser.swift`
- Create: `Sources/PointFreeKit/Parsing/BlogContentParser.swift`
- Create: `Tests/PointFreeKitTests/Fixtures/blog-atom.xml`
- Test: `Tests/PointFreeKitTests/BlogTests.swift`

**Interfaces:**
- Consumes: `InlineMarkdown.render`, `InlineMarkdown.rawText`, `Transcript.Block`, `PointFreeError`.
- Produces: `BlogPost { number: Int; slug: String; title: String; url: URL; updated: Date; contentHTML: String }`, `BlogPostRef { number: Int }` с `parse(_:)`, `BlogFeedParser.parse(xml: String) throws -> [BlogPost]`, `BlogContentParser.blocks(html: String) throws -> [Transcript.Block]`.

Фид `https://www.pointfree.co/blog/feed/atom.xml` публичный, 230 записей, каждая с полным HTML в `<content type="html"><![CDATA[…]]></content>`. Форма записи:
```xml
<entry><title>LazyState 1.0: Now available to everyone</title>
<link href="https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone"></link>
<updated>2026-09-14T00:00:00Z</updated>
<id>https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone</id>
<content type="html"><![CDATA[<div class=" md-ctn"><p>…</p><pre><code>…</code></pre><h2>…</h2><ul><li>…</li></ul></div>]]></content></entry>
```
Номер поста — ведущее число slug. Страницы блога не запрашиваются вовсе.

- [ ] **Step 1: Фикстура `blog-atom.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<title>Point-Free Pointers</title>
<entry><title>Announcing Point-Free Pointers!</title><link href="https://www.pointfree.co/blog/posts/1-announcing-point-free-pointers"></link><updated>2018-04-23T04:01:02Z</updated><id>https://www.pointfree.co/blog/posts/1-announcing-point-free-pointers</id><content type="html"><![CDATA[<div class=" md-ctn"><p>First post.</p></div>]]></content></entry>
<entry><title>LazyState 1.0: Now available to everyone</title><link href="https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone"></link><updated>2026-09-14T00:00:00Z</updated><id>https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone</id><content type="html"><![CDATA[<div class=" md-ctn"><p>We are excited to announce <a href="https://github.com/pointfreeco/swiftui-lazy-state">LazyState</a> <strong>1.0</strong>.</p><h2>Usage</h2><pre><code>@LazyState var model = Model()
</code></pre><ul><li>One</li><li>Two with <code>code</code></li></ul><blockquote><p>Quoted.</p></blockquote></div>]]></content></entry>
</feed>
```

- [ ] **Step 2: Тесты**

```swift
import Foundation
import Testing
@testable import PointFreeKit

@Test func parsesAtomFeedEntries() throws {
  let posts = try BlogFeedParser.parse(xml: fixtureString("blog-atom.xml"))
  #expect(posts.count == 2)
  let post = try #require(posts.first { $0.number == 228 })
  #expect(post.slug == "228-lazystate-1-0-now-available-to-everyone")
  #expect(post.title == "LazyState 1.0: Now available to everyone")
  #expect(post.url.absoluteString == "https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone")
  #expect(post.updated == Date(timeIntervalSince1970: 1_789_344_000))
  #expect(post.contentHTML.contains("<pre><code>@LazyState"))
}

@Test func convertsPostContentToBlocks() throws {
  let post = try #require(try BlogFeedParser.parse(xml: fixtureString("blog-atom.xml")).first { $0.number == 228 })
  let blocks = try BlogContentParser.blocks(html: post.contentHTML)
  #expect(blocks == [
    .paragraph("We are excited to announce [LazyState](https://github.com/pointfreeco/swiftui-lazy-state) **1.0**."),
    .heading("Usage"),
    .code("@LazyState var model = Model()\n"),
    .listItem("One"),
    .listItem("Two with `code`"),
    .quote("Quoted."),
  ])
}

@Test(arguments: [
  ("228", 228), ("228-lazystate-1-0-now-available-to-everyone", 228),
  ("https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone", 228), ("/blog/posts/1-announcing", 1),
])
func parsesBlogPostRefs(raw: String, number: Int) throws {
  #expect(try #require(BlogPostRef.parse(raw)).number == number)
}

@Test(arguments: ["", "lazystate", "https://www.pointfree.co/episodes/ep1-functions"])
func rejectsBadBlogRefs(raw: String) {
  #expect(BlogPostRef.parse(raw) == nil)
}

@Test func malformedFeedIsStructureChange() {
  #expect(throws: PointFreeError.self) {
    _ = try BlogFeedParser.parse(xml: "<html>not a feed</html>")
  }
}
```

- [ ] **Step 3: Запустить — не компилируется**

Run: `swift test --filter BlogTests`

- [ ] **Step 4: Реализация**

`Sources/PointFreeKit/Models/BlogPost.swift`:
```swift
import Foundation

public struct BlogPost: Equatable, Sendable {
  public var number: Int
  public var slug: String
  public var title: String
  public var url: URL
  public var updated: Date
  public var contentHTML: String

  public init(number: Int, slug: String, title: String, url: URL, updated: Date, contentHTML: String) {
    self.number = number; self.slug = slug; self.title = title; self.url = url; self.updated = updated; self.contentHTML = contentHTML
  }
}

public struct BlogPostRef: Equatable, Sendable {
  public var number: Int

  /// "228", "228-slug", "https://www.pointfree.co/blog/posts/228-slug", "/blog/posts/228-slug"
  public static func parse(_ raw: String) -> BlogPostRef? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let q = text.firstIndex(where: { $0 == "?" || $0 == "#" }) { text = String(text[..<q]) }
    if text.contains("/") {
      guard let range = text.range(of: "/blog/posts/") else { return nil }
      text = String(text[range.upperBound...])
    }
    while text.hasSuffix("/") { text.removeLast() }
    guard let match = text.wholeMatch(of: /(\d+)(?:-[A-Za-z0-9-]*)?/), let number = Int(match.1) else { return nil }
    return BlogPostRef(number: number)
  }
}
```

`Sources/PointFreeKit/Parsing/BlogFeedParser.swift`:
```swift
import Foundation

public enum BlogFeedParser {
  public static func parse(xml: String) throws -> [BlogPost] {
    let delegate = AtomDelegate()
    let parser = XMLParser(data: Data(xml.utf8))
    parser.delegate = delegate
    guard parser.parse(), delegate.sawFeed else {
      throw PointFreeError.structureChanged("blog atom feed", URL(string: "https://www.pointfree.co/blog/feed/atom.xml"))
    }
    return delegate.posts
  }

  private final class AtomDelegate: NSObject, XMLParserDelegate {
    var posts: [BlogPost] = []
    var sawFeed = false
    private var inEntry = false
    private var currentElement = ""
    private var title = "", link = "", updated = "", content = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
      currentElement = name
      switch name {
      case "feed": sawFeed = true
      case "entry": inEntry = true; title = ""; link = ""; updated = ""; content = ""
      case "link" where inEntry: link = attributes["href"] ?? link
      default: break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      guard inEntry else { return }
      switch currentElement {
      case "title": title += string
      case "updated": updated += string
      case "content": content += string
      default: break
      }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
      guard inEntry, currentElement == "content" else { return }
      content += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
      currentElement = ""
      guard name == "entry", inEntry else { return }
      inEntry = false
      guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)),
            let slug = url.pathComponents.last,
            let ref = BlogPostRef.parse(slug),
            let date = try? Date(updated.trimmingCharacters(in: .whitespacesAndNewlines), strategy: .iso8601)
      else { return }
      posts.append(BlogPost(number: ref.number, slug: slug, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            url: url, updated: date, contentHTML: content))
    }
  }
}
```

`Sources/PointFreeKit/Parsing/BlogContentParser.swift`:
```swift
import Foundation
import SwiftSoup

public enum BlogContentParser {
  public static func blocks(html: String) throws -> [Transcript.Block] {
    let doc = try SwiftSoup.parseBodyFragment(html)
    var blocks: [Transcript.Block] = []
    for node in try doc.body()!.select("h1, h2, h3, h4, h5, h6, p, pre, li, blockquote") {
      let insideQuoteOrItem = node.parents().contains { ["li", "blockquote"].contains($0.tagName()) }
      switch node.tagName() {
      case "h1", "h2", "h3", "h4", "h5", "h6":
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { blocks.append(.heading(text)) }
      case "p":
        guard !insideQuoteOrItem else { continue }
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { blocks.append(.paragraph(text)) }
      case "pre":
        let code = try node.select("code").first() ?? node
        var text = InlineMarkdown.rawText(code)
        if !text.hasSuffix("\n") && text.contains("\n") { text += "\n" }
        blocks.append(.code(text))
      case "li":
        let text = try InlineMarkdown.render(node)
        if !text.isEmpty { blocks.append(.listItem(text)) }
      case "blockquote":
        let text = try node.select("p").map { try InlineMarkdown.render($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        let quote = try (text.isEmpty ? InlineMarkdown.render(node) : text)
        blocks.append(.quote(quote))
      default: break
      }
    }
    return blocks
  }
}
```

- [ ] **Step 5: Тесты проходят**

Run: `swift test --filter BlogTests`
Expected: PASS. Дата `1_789_344_000` = 2026-09-14T00:00:00Z. Если `XMLParser` отдаёт CDATA через `foundCharacters`, а не `foundCDATA`, код уже собирает оба; проверить, что HTML не экранирован дважды.

- [ ] **Step 6: Commit**

```bash
git add Sources/PointFreeKit/Models/BlogPost.swift Sources/PointFreeKit/Parsing/BlogFeedParser.swift Sources/PointFreeKit/Parsing/BlogContentParser.swift Tests/PointFreeKitTests/Fixtures/blog-atom.xml Tests/PointFreeKitTests/BlogTests.swift
git commit -m "feat: blog posts from the Atom feed"
```

---

### Task 12: Инструменты MCP (логика без транспорта)

**Files:**
- Create: `Sources/PointFreeKit/Tools/ToolArguments.swift`
- Create: `Sources/PointFreeKit/Tools/ToolDefinitions.swift`
- Create: `Sources/PointFreeKit/Tools/LoginLauncher.swift`
- Create: `Sources/PointFreeKit/Tools/ToolCatalog.swift`
- Test: `Tests/PointFreeKitTests/ToolCatalogTests.swift`

**Interfaces:**
- Consumes: `PointFreeClient`, `SessionStore`, парсеры, `MarkdownRenderer`.
- Consumes также: `BlogFeedParser`, `BlogContentParser`, `BlogPost`, `BlogPostRef` из Task 11.
- Produces: `ToolArguments` (Decodable из JSON-объекта; `string(_:)`, `int(_:)`, `bool(_:)`), `ToolDefinition { name, description, inputSchemaJSON: String }`, `ToolDefinitions.all: [ToolDefinition]`, `ToolOutput { text, isError }`, `ToolCatalog.call(name: String, arguments: ToolArguments) async -> ToolOutput`, `LoginLauncher.run() async throws -> LoginOutcome` (dependency `\.loginLauncher`), `LoginOutcome { case success, cancelled, failed(String) }`.

Порядок: Task 11 (блог) выполняется до этой задачи, потому что каталог инструментов ссылается на парсеры блога.

- [ ] **Step 1: Тесты**

```swift
import Dependencies
import Foundation
import Testing
@testable import PointFreeKit

private func args(_ json: String) throws -> ToolArguments {
  try JSONDecoder().decode(ToolArguments.self, from: Data(json.utf8))
}

private func detailJSON() throws -> EpisodeDetail {
  try PointFreeJSON.decoder.decode(EpisodeDetail.self, from: fixture("episode-381.json"))
}

@Test func toolDefinitionsAreValidJSONSchemas() throws {
  #expect(ToolDefinitions.all.map(\.name) == ["searchPointFree", "fetchEpisode", "listEpisodes", "fetchCollection", "listBlogPosts", "fetchBlogPost", "login"])
  for def in ToolDefinitions.all {
    let obj = try JSONSerialization.jsonObject(with: Data(def.inputSchemaJSON.utf8)) as? [String: Any]
    #expect(obj?["type"] as? String == "object", "\(def.name)")
    #expect(obj?["properties"] is [String: Any], "\(def.name)")
  }
}

@Test func toolArgumentsDecodeMixedTypes() throws {
  let a = try args(#"{"query":"x","limit":5,"force":true,"ratio":2.0}"#)
  #expect(a.string("query") == "x")
  #expect(a.int("limit") == 5)
  #expect(a.int("ratio") == 2)
  #expect(a.bool("force") == true)
  #expect(a.string("missing") == nil)
}

@Test func searchToolRendersResults() async throws {
  let out = try await withDependencies {
    $0.pointFreeClient.search = { q in
      #expect(q == SearchQuery(query: "Sendable", scope: .dialogue, access: nil, sort: nil))
      return try fixtureString("search.html")
    }
    $0.pointFreeClient.episodes = { try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: fixture("episodes.json")) }
  } operation: {
    await ToolCatalog().call(name: "searchPointFree", arguments: try args(#"{"query":"Sendable","scope":"dialogue"}"#))
  }
  #expect(!out.isError)
  #expect(out.text.contains("## #381: Designing for Isolation: Naively (Members only)"))
}

@Test func searchToolRejectsBadScope() async throws {
  let out = await ToolCatalog().call(name: "searchPointFree", arguments: try args(#"{"query":"x","scope":"everything"}"#))
  #expect(out.isError)
  #expect(out.text.contains("scope"))
}

@Test func fetchEpisodeRendersTranscript() async throws {
  let out = try await withDependencies {
    $0.pointFreeClient.episode = { id in #expect(id == 381); return try detailJSON() }
    $0.pointFreeClient.episodePage = { path in #expect(path == "381"); return try fixtureString("episode-free.html") }
  } operation: {
    await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"381"}"#))
  }
  #expect(!out.isError)
  #expect(out.text.contains("# Episode #381"))
  #expect(out.text.contains("## Introduction"))
}

@Test func fetchEpisodeWithoutSessionAsksToLogin() async throws {
  let out = try await withDependencies {
    $0.pointFreeClient.episode = { _ in try detailJSON() }
    $0.pointFreeClient.episodePage = { _ in try fixtureString("episode-locked.html") }
    $0.sessionStore.load = { nil }
  } operation: {
    await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"ep381-designing-for-isolation-naively"}"#))
  }
  #expect(out.isError)
  #expect(out.text == PointFreeError.loginRequired.userMessage)
}

@Test func fetchEpisodeWithDeadSessionClearsItAndAsksToLogin() async throws {
  final class Flag: @unchecked Sendable { var cleared = false }
  let flag = Flag()
  let out = try await withDependencies {
    $0.pointFreeClient.episode = { _ in try detailJSON() }
    $0.pointFreeClient.episodePage = { _ in try fixtureString("episode-locked.html") }
    $0.pointFreeClient.validateSession = { _ in false }
    $0.sessionStore.load = { Session(cookie: "OLD", expiresAt: .distantFuture, savedAt: .distantPast) }
    $0.sessionStore.clear = { flag.cleared = true }
    $0.date.now = Date()
  } operation: {
    await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"381"}"#))
  }
  #expect(out.isError)
  #expect(out.text == PointFreeError.sessionExpired.userMessage)
  #expect(flag.cleared)
}

@Test func fetchEpisodeWithValidSessionButTruncatedKeepsSession() async throws {
  final class Flag: @unchecked Sendable { var cleared = false }
  let flag = Flag()
  let out = try await withDependencies {
    $0.pointFreeClient.episode = { _ in try detailJSON() }
    $0.pointFreeClient.episodePage = { _ in try fixtureString("episode-locked.html") }
    $0.pointFreeClient.validateSession = { _ in true }
    $0.sessionStore.load = { Session(cookie: "OK", expiresAt: .distantFuture, savedAt: .distantPast) }
    $0.sessionStore.clear = { flag.cleared = true }
    $0.date.now = Date()
  } operation: {
    await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"381"}"#))
  }
  #expect(out.isError)
  #expect(out.text == PointFreeError.subscriptionRequired.userMessage)
  #expect(!flag.cleared)
}

@Test func fetchEpisodeRejectsBadReference() async throws {
  let out = await ToolCatalog().call(name: "fetchEpisode", arguments: try args(#"{"episode":"functions"}"#))
  #expect(out.isError)
  #expect(out.text.contains("episode"))
}

@Test func listEpisodesFiltersAndLimits() async throws {
  let out = try await withDependencies {
    $0.pointFreeClient.episodes = { try PointFreeJSON.decoder.decode([EpisodeSummary].self, from: fixture("episodes.json")) }
  } operation: {
    await ToolCatalog().call(name: "listEpisodes", arguments: try args(#"{"filter":"isolation","limit":10}"#))
  }
  #expect(out.text.contains("#381"))
  #expect(!out.text.contains("#379"))
}

@Test func fetchCollectionDispatchesByArguments() async throws {
  let catalog = ToolCatalog()
  let index = try await withDependencies {
    $0.pointFreeClient.collectionsPage = { try fixtureString("collections.html") }
  } operation: { await catalog.call(name: "fetchCollection", arguments: try args("{}")) }
  #expect(index.text.contains("`composable-architecture`"))

  let sections = try await withDependencies {
    $0.pointFreeClient.collectionPage = { slug in #expect(slug == "composable-architecture"); return try fixtureString("collection.html") }
  } operation: { await catalog.call(name: "fetchCollection", arguments: try args(#"{"slug":"composable-architecture"}"#)) }
  #expect(sections.text.contains("`testing`"))

  let episodes = try await withDependencies {
    $0.pointFreeClient.sectionPage = { slug, section in #expect(slug == "composable-architecture" && section == "testing"); return try fixtureString("section.html") }
  } operation: { await catalog.call(name: "fetchCollection", arguments: try args(#"{"slug":"composable-architecture","section":"testing"}"#)) }
  #expect(episodes.text.contains("#82"))
}

@Test func blogToolsListAndFetchFromFeed() async throws {
  let catalog = ToolCatalog()
  let list = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
  } operation: { await catalog.call(name: "listBlogPosts", arguments: try args(#"{"filter":"lazystate","limit":5}"#)) }
  #expect(!list.isError)
  #expect(list.text.contains("#228 LazyState 1.0"))
  #expect(!list.text.contains("#1 Announcing"))

  let post = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
  } operation: { await catalog.call(name: "fetchBlogPost", arguments: try args(#"{"post":"228"}"#)) }
  #expect(!post.isError)
  #expect(post.text.hasPrefix("# LazyState 1.0"))
  #expect(post.text.contains("```swift"))

  let missing = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
  } operation: { await catalog.call(name: "fetchBlogPost", arguments: try args(#"{"post":"999"}"#)) }
  #expect(missing.isError)
  #expect(missing.text.contains("999"))
}

@Test func loginToolReportsExistingValidSession() async throws {
  let out = try await withDependencies {
    $0.sessionStore.load = { Session(cookie: "OK", expiresAt: Date(timeIntervalSince1970: 200), savedAt: Date(timeIntervalSince1970: 0)) }
    $0.pointFreeClient.validateSession = { _ in true }
    $0.date.now = Date(timeIntervalSince1970: 100)
    $0.loginLauncher.run = { Issue.record("must not launch"); return .cancelled }
  } operation: { await ToolCatalog().call(name: "login", arguments: try args("{}")) }
  #expect(!out.isError)
  #expect(out.text.contains("Already signed in"))
}

@Test func loginToolLaunchesWindowAndInvalidatesCache() async throws {
  final class Flag: @unchecked Sendable { var invalidated = false }
  let flag = Flag()
  let out = try await withDependencies {
    $0.sessionStore.load = { flag.invalidated ? Session(cookie: "NEW", expiresAt: .distantFuture, savedAt: .distantPast) : nil }
    $0.loginLauncher.run = { .success }
    $0.pointFreeClient.invalidateCache = { flag.invalidated = true }
  } operation: { await ToolCatalog().call(name: "login", arguments: try args("{}")) }
  #expect(!out.isError)
  #expect(out.text.contains("Signed in"))
  #expect(flag.invalidated)
}

@Test func loginToolReportsCancellation() async throws {
  let out = try await withDependencies {
    $0.sessionStore.load = { nil }
    $0.loginLauncher.run = { .cancelled }
  } operation: { await ToolCatalog().call(name: "login", arguments: try args("{}")) }
  #expect(out.isError)
  #expect(out.text.contains("cancelled"))
}

@Test func unknownToolIsError() async throws {
  let out = await ToolCatalog().call(name: "nope", arguments: try args("{}"))
  #expect(out.isError)
}
```

- [ ] **Step 2: Запустить — не компилируется**

- [ ] **Step 3: Реализация**

`Sources/PointFreeKit/Tools/ToolArguments.swift`:
```swift
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
```

`Sources/PointFreeKit/Tools/ToolDefinitions.swift`:
```swift
public struct ToolDefinition: Equatable, Sendable {
  public var name: String
  public var description: String
  public var inputSchemaJSON: String
}

public enum ToolDefinitions {
  public static let all: [ToolDefinition] = [
    ToolDefinition(
      name: "searchPointFree",
      description: "Search the Point-Free (pointfree.co) video catalog: transcripts, code and titles of all episodes about Swift, SwiftUI, TCA, dependencies, navigation, SQLite, concurrency. Returns matching episodes with snippets and timestamped chapter links. No login needed.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "query":{"type":"string","description":"Search terms, e.g. \\"Sendable\\", \\"@Shared\\", \\"navigation stack\\""},
        "scope":{"type":"string","enum":["dialogue","code","titles"],"description":"Limit matching to spoken dialogue, code samples, or episode titles"},
        "access":{"type":"string","enum":["free","subscriber-only"],"description":"Only free or only members-only episodes"},
        "sort":{"type":"string","enum":["newest","oldest"],"description":"Sort order; default is relevance"}
      },"required":["query"]}
      """
    ),
    ToolDefinition(
      name: "fetchEpisode",
      description: "Fetch a Point-Free episode as markdown: metadata, references, link to code samples, and the full transcript with code blocks and timestamped chapters. Accepts an episode number (381), slug (ep381-designing-for-isolation-naively) or URL. Members-only episodes require the `login` tool first. Use `section` to fetch one chapter and save context.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "episode":{"type":"string","description":"Episode number, slug, or pointfree.co URL (a #tNNN fragment selects a section)"},
        "section":{"type":"string","description":"Optional chapter: timestamp like \\"t349\\" or \\"5:49\\", or chapter slug like \\"introduction\\""}
      },"required":["episode"]}
      """
    ),
    ToolDefinition(
      name: "listEpisodes",
      description: "List Point-Free episodes, newest first: number, title, date, duration and access (Free / Members only). Optional title filter.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "filter":{"type":"string","description":"Case-insensitive substring to match in the title"},
        "limit":{"type":"integer","description":"Maximum number of episodes to return (default 50)"}
      }}
      """
    ),
    ToolDefinition(
      name: "fetchCollection",
      description: "Browse Point-Free collections (curated learning paths). Without arguments lists all collections; with `slug` lists the collection's sections; with `slug` and `section` lists the episodes of that section.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "slug":{"type":"string","description":"Collection slug, e.g. composable-architecture"},
        "section":{"type":"string","description":"Section slug within the collection, e.g. testing"}
      }}
      """
    ),
    ToolDefinition(
      name: "listBlogPosts",
      description: "List posts from the Point-Free Pointers blog (library release announcements, migration guides, monthly recaps), newest first. Optional title filter. No login needed.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "filter":{"type":"string","description":"Case-insensitive substring to match in the post title"},
        "limit":{"type":"integer","description":"Maximum number of posts to return (default 30)"}
      }}
      """
    ),
    ToolDefinition(
      name: "fetchBlogPost",
      description: "Fetch a Point-Free Pointers blog post as markdown with code blocks. Accepts a post number (228), slug (228-lazystate-1-0-now-available-to-everyone) or URL. No login needed.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "post":{"type":"string","description":"Post number, slug, or pointfree.co/blog/posts URL"}
      },"required":["post"]}
      """
    ),
    ToolDefinition(
      name: "login",
      description: "Sign in to pointfree.co with GitHub to access members-only transcripts. Opens a browser window on this Mac; the user completes the login there. Reports the current session if already signed in; pass force=true to sign in again.",
      inputSchemaJSON: """
      {"type":"object","properties":{
        "force":{"type":"boolean","description":"Re-authenticate even if a session exists"}
      }}
      """
    ),
  ]
}
```

`Sources/PointFreeKit/Tools/LoginLauncher.swift`:
```swift
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
    process.standardOutput = FileHandle.standardError
    process.standardError = FileHandle.standardError
    let watchdog = Task {
      try? await Task.sleep(for: .seconds(320))
      if process.isRunning { process.terminate() }
    }
    defer { watchdog.cancel() }
    // terminationHandler ставится до run(), иначе быстрый выход потеряет continuation.
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do { try process.run() } catch { continuation.resume(throwing: error) }
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
```

`Sources/PointFreeKit/Tools/ToolCatalog.swift`:
```swift
import Dependencies
import Foundation

public struct ToolOutput: Equatable, Sendable {
  public var text: String
  public var isError: Bool
  public init(text: String, isError: Bool = false) { self.text = text; self.isError = isError }
}

public struct ToolCatalog: Sendable {
  @Dependency(\.pointFreeClient) var client
  @Dependency(\.sessionStore) var sessionStore
  @Dependency(\.loginLauncher) var loginLauncher
  @Dependency(\.date.now) var now

  public init() {}

  public func call(name: String, arguments: ToolArguments) async -> ToolOutput {
    do {
      switch name {
      case "searchPointFree": return try await search(arguments)
      case "fetchEpisode": return try await fetchEpisode(arguments)
      case "listEpisodes": return try await listEpisodes(arguments)
      case "fetchCollection": return try await fetchCollection(arguments)
      case "listBlogPosts": return try await listBlogPosts(arguments)
      case "fetchBlogPost": return try await fetchBlogPost(arguments)
      case "login": return try await login(arguments)
      default: return ToolOutput(text: "Unknown tool: \(name)", isError: true)
      }
    } catch let error as PointFreeError {
      return ToolOutput(text: error.userMessage, isError: true)
    } catch {
      return ToolOutput(text: "Unexpected error: \(error)", isError: true)
    }
  }

  func search(_ args: ToolArguments) async throws -> ToolOutput {
    guard let query = args.string("query") else { throw PointFreeError.invalidArgument("`query` is required") }
    let scope = try enumArg(args, "scope", SearchQuery.Scope.self)
    let access = try enumArg(args, "access", SearchQuery.Access.self)
    let sort = try enumArg(args, "sort", SearchQuery.Sort.self)
    let q = SearchQuery(query: query, scope: scope, access: access, sort: sort)
    let html = try await client.search(q)
    let page = try SearchPageParser.parse(html: html, url: q.url)
    let episodes = (try? await client.episodes()) ?? []
    let byID = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, $0) })
    return ToolOutput(text: MarkdownRenderer.search(query: q, page: page, episodes: byID))
  }

  func fetchEpisode(_ args: ToolArguments) async throws -> ToolOutput {
    guard let raw = args.string("episode") else { throw PointFreeError.invalidArgument("`episode` is required") }
    guard var ref = EpisodeRef.parse(raw) else {
      throw PointFreeError.invalidArgument("`episode` must be a number (381), a slug (ep381-…) or a pointfree.co episode URL; got \"\(raw)\"")
    }
    if let sectionText = args.string("section") { ref.section = SectionRef.parse(sectionText) }

    let detail = try await client.episode(ref.number)
    let html = try await client.episodePage(ref.pathComponent)
    let page = try EpisodePageParser.parse(html: html, url: detail.pageURL)

    if page.isTruncated && detail.subscriberOnly {
      guard let session = try sessionStore.load() else { throw PointFreeError.loginRequired }
      if session.isExpired(now: now) {
        try sessionStore.clear()
        throw PointFreeError.sessionExpired
      }
      if try await client.validateSession(session.cookie) {
        throw PointFreeError.subscriptionRequired
      } else {
        try sessionStore.clear()
        await client.invalidateCache()
        throw PointFreeError.sessionExpired
      }
    }
    if !page.transcript.hasBody {
      throw PointFreeError.structureChanged("transcript body", detail.pageURL)
    }
    return ToolOutput(text: try MarkdownRenderer.episode(detail: detail, transcript: page.transcript, section: ref.section))
  }

  func listEpisodes(_ args: ToolArguments) async throws -> ToolOutput {
    let limit = max(1, args.int("limit") ?? 50)
    var episodes = try await client.episodes().sorted { $0.sequence > $1.sequence }
    if let filter = args.string("filter")?.lowercased() {
      episodes = episodes.filter { $0.title.lowercased().contains(filter) }
    }
    return ToolOutput(text: MarkdownRenderer.episodeList(Array(episodes.prefix(limit))))
  }

  func fetchCollection(_ args: ToolArguments) async throws -> ToolOutput {
    guard let slug = args.string("slug")?.lowercased() else {
      let list = try CollectionsParser.parseIndex(html: try await client.collectionsPage())
      return ToolOutput(text: MarkdownRenderer.collections(list))
    }
    guard let section = args.string("section")?.lowercased() else {
      let c = try CollectionsParser.parseCollection(html: try await client.collectionPage(slug), slug: slug)
      return ToolOutput(text: MarkdownRenderer.collection(title: c.title, slug: slug, sections: c.sections))
    }
    let s = try CollectionsParser.parseSection(html: try await client.sectionPage(slug, section))
    return ToolOutput(text: MarkdownRenderer.section(collectionSlug: slug, sectionSlug: section, title: s.title, groups: s.groups))
  }

  func listBlogPosts(_ args: ToolArguments) async throws -> ToolOutput {
    let limit = max(1, args.int("limit") ?? 30)
    var posts = try BlogFeedParser.parse(xml: try await client.blogFeed()).sorted { $0.number > $1.number }
    if let filter = args.string("filter")?.lowercased() {
      posts = posts.filter { $0.title.lowercased().contains(filter) }
    }
    return ToolOutput(text: MarkdownRenderer.blogList(Array(posts.prefix(limit))))
  }

  func fetchBlogPost(_ args: ToolArguments) async throws -> ToolOutput {
    guard let raw = args.string("post") else { throw PointFreeError.invalidArgument("`post` is required") }
    guard let ref = BlogPostRef.parse(raw) else {
      throw PointFreeError.invalidArgument("`post` must be a number (228), a slug (228-…) or a pointfree.co blog URL; got \"\(raw)\"")
    }
    let posts = try BlogFeedParser.parse(xml: try await client.blogFeed())
    guard let post = posts.first(where: { $0.number == ref.number }) else {
      throw PointFreeError.invalidArgument("Blog post \(ref.number) not found in the feed")
    }
    let blocks = try BlogContentParser.blocks(html: post.contentHTML)
    return ToolOutput(text: MarkdownRenderer.blogPost(post, blocks: blocks))
  }

  func login(_ args: ToolArguments) async throws -> ToolOutput {
    let force = args.bool("force") ?? false
    if !force, let session = try sessionStore.load(), !session.isExpired(now: now),
       try await client.validateSession(session.cookie) {
      let days = Int(session.expiresAt.timeIntervalSince(now) / 86_400)
      return ToolOutput(text: "Already signed in to pointfree.co. Session valid until \(session.expiresAt) (about \(days) more day(s)). Pass force=true to sign in again.")
    }
    switch try await loginLauncher.run() {
    case .success:
      await client.invalidateCache()
      guard let saved = try sessionStore.load() else {
        return ToolOutput(text: PointFreeError.loginFailed("login finished but no session was saved").userMessage, isError: true)
      }
      return ToolOutput(text: "Signed in to pointfree.co. Session valid until \(saved.expiresAt). Members-only transcripts are now available; retry your request.")
    case .cancelled:
      return ToolOutput(text: "Login was cancelled (the window was closed before signing in).", isError: true)
    case .failed(let message):
      return ToolOutput(text: PointFreeError.loginFailed(message).userMessage, isError: true)
    }
  }

  private func enumArg<T: RawRepresentable & CaseIterable>(_ args: ToolArguments, _ key: String, _ type: T.Type) throws -> T? where T.RawValue == String {
    guard let raw = args.string(key) else { return nil }
    guard let value = T(rawValue: raw.lowercased()) else {
      let allowed = T.allCases.map { "\($0.rawValue)" }.joined(separator: ", ")
      throw PointFreeError.invalidArgument("`\(key)` must be one of: \(allowed); got \"\(raw)\"")
    }
    return value
  }
}
```

- [ ] **Step 4: Тесты проходят**

Run: `swift test --filter ToolCatalogTests`
Expected: 16 тестов PASS. Если `@Dependency` внутри `struct ToolCatalog` захватывает live-значения в момент `init()` — создавать `ToolCatalog()` внутри `operation:` (как в тестах) и в `Serve` создавать после `prepareDependencies`.

- [ ] **Step 5: Commit**

```bash
git add Sources/PointFreeKit/Tools Tests/PointFreeKitTests/ToolCatalogTests.swift
git commit -m "feat: MCP tool catalog with search, episode, list, collection, blog and login"
```

---

### Task 13: Исполняемый сервер: `serve`, `status`, `logout`

**Files:**
- Modify: `Sources/PointFreeMCP/PointFreeMCPCommand.swift`
- Create: `Sources/PointFreeMCP/Commands/Serve.swift`
- Create: `Sources/PointFreeMCP/Commands/Status.swift`
- Create: `Sources/PointFreeMCP/Commands/Logout.swift`
- Create: `Sources/PointFreeMCP/Server/MCPServerFactory.swift`

**Interfaces:**
- Consumes: `ToolDefinitions.all`, `ToolCatalog`, `ToolArguments`, `SessionStore`, `PointFreeClient`.
- Produces: бинарь `pointfree-mcp` с подкомандами `serve` (по умолчанию), `status`, `logout`; `login` добавляется в Task 14.

- [ ] **Step 1: Корневая команда**

```swift
import ArgumentParser
import PointFreeKit

@main
struct PointFreeMCPCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pointfree-mcp",
    abstract: "MCP server for pointfree.co",
    version: PointFreeKit.version,
    subcommands: [Serve.self, Status.self, Logout.self],
    defaultSubcommand: Serve.self
  )
}
```

- [ ] **Step 2: Фабрика сервера**

`Sources/PointFreeMCP/Server/MCPServerFactory.swift`:
```swift
import Foundation
import MCP
import PointFreeKit

enum MCPServerFactory {
  static func make(catalog: ToolCatalog) async throws -> Server {
    let server = Server(
      name: "pointfree",
      version: PointFreeKit.version,
      capabilities: .init(tools: .init(listChanged: false))
    )

    let tools: [Tool] = try ToolDefinitions.all.map { def in
      let schema = try JSONDecoder().decode(Value.self, from: Data(def.inputSchemaJSON.utf8))
      return Tool(name: def.name, description: def.description, inputSchema: schema)
    }

    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: tools)
    }

    await server.withMethodHandler(CallTool.self) { params in
      let arguments: ToolArguments
      if let raw = params.arguments {
        let data = try JSONEncoder().encode(raw)
        arguments = try JSONDecoder().decode(ToolArguments.self, from: data)
      } else {
        arguments = ToolArguments()
      }
      let output = await catalog.call(name: params.name, arguments: arguments)
      return .init(content: [.text(text: output.text, annotations: nil, _meta: nil)], isError: output.isError)
    }

    return server
  }
}
```

- [ ] **Step 3: Команда serve**

`Sources/PointFreeMCP/Commands/Serve.swift`:
```swift
import ArgumentParser
import Foundation
import Logging
import MCP
import PointFreeKit

struct Serve: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Run the MCP server over stdio (default).")

  func run() async throws {
    // stdout принадлежит JSON-RPC; все логи только в stderr.
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardError(label: label)
      handler.logLevel = .warning
      return handler
    }
    let catalog = ToolCatalog()
    let server = try await MCPServerFactory.make(catalog: catalog)
    let transport = StdioTransport(logger: Logger(label: "pointfree-mcp.stdio"))
    try await server.start(transport: transport)
    await server.waitUntilCompleted()
  }
}
```

- [ ] **Step 4: Команды status и logout**

`Sources/PointFreeMCP/Commands/Status.swift`:
```swift
import ArgumentParser
import Dependencies
import Foundation
import PointFreeKit

struct Status: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Show the saved pointfree.co session.")

  func run() async throws {
    @Dependency(\.sessionStore) var store
    @Dependency(\.pointFreeClient) var client
    guard let session = try store.load() else {
      print("Not signed in. Run `pointfree-mcp login`.")
      return
    }
    if session.isExpired(now: Date()) {
      print("Session expired at \(session.expiresAt). Run `pointfree-mcp login`.")
      return
    }
    let valid = try await client.validateSession(session.cookie)
    print(valid ? "Signed in; session valid until \(session.expiresAt)." : "Session file exists but pointfree.co rejected it. Run `pointfree-mcp login`.")
  }
}
```

`Sources/PointFreeMCP/Commands/Logout.swift`:
```swift
import ArgumentParser
import Dependencies
import PointFreeKit

struct Logout: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Delete the saved pointfree.co session.")

  func run() throws {
    @Dependency(\.sessionStore) var store
    try store.clear()
    print("Session removed.")
  }
}
```

- [ ] **Step 5: Сборка и дымовой тест протокола**

Run: `swift build`
Затем:
```bash
printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | .build/debug/pointfree-mcp serve
```
Expected: две JSON-строки ответов (initialize и список из 7 инструментов), в stdout ничего кроме JSON. Затем (`sleep` держит stdin открытым, пока обработчик ходит в сеть; при EOF на stdin сервер завершается сразу):
```bash
(printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fetchEpisode","arguments":{"episode":"1","section":"introduction"}}}'; sleep 15) \
  | .build/debug/pointfree-mcp serve
```
Expected: ответ содержит `# Episode #1: Functions` и одну главу. `pointfree-mcp status` печатает «Not signed in». Аналогичный вызов `{"name":"fetchBlogPost","arguments":{"post":"228"}}` возвращает пост с блоками кода.

- [ ] **Step 6: Commit**

```bash
git add Sources/PointFreeMCP
git commit -m "feat: stdio MCP server with serve, status and logout commands"
```

---

### Task 14: Окно входа (AppKit + WKWebView) и команда `login`

**Files:**
- Create: `Sources/PointFreeMCP/LoginWindow/LoginWindowController.swift`
- Create: `Sources/PointFreeMCP/Commands/Login.swift`
- Modify: `Sources/PointFreeMCP/PointFreeMCPCommand.swift` (добавить `Login.self` в `subcommands`)

**Interfaces:**
- Consumes: `Session`, `SessionStore`, `PointFreeClient.validateSession`, `PointFreeClient.cookieName`.
- Produces: команда `pointfree-mcp login [--cookie <value>] [--timeout <s>]`; коды выхода: 0 — сессия сохранена, 1 — отменено пользователем, 2 — cookie отвергнута сайтом, 3 — таймаут, 4 — ошибка (сеть, запись файла). `LoginLauncher.liveValue` из Task 12 сопоставляет эти коды.

Механика: `NSApplication.shared` с политикой `.regular`, окно 900×720 с `WKWebView`; `WKWebsiteDataStore(forIdentifier:)` с фиксированным UUID, чтобы профиль WebKit сохранялся между запусками и GitHub помнил пользователя. Наблюдатель `WKHTTPCookieStoreObserver` при каждом изменении ищет `pf_session` для домена `www.pointfree.co` (HttpOnly cookie в `allCookies` возвращаются). Сайт ставит `pf_session` и анонимному посетителю (например, состояние OAuth перед редиректом на GitHub), поэтому найденная cookie сначала проверяется запросом `validateSession`; отвергнутые значения запоминаются и окно ждёт дальше. Только валидная cookie останавливает цикл `NSApp.stop`, который «будится» пустым событием.

- [ ] **Step 1: Контроллер окна**

```swift
import AppKit
import Foundation
import PointFreeKit
import WebKit

@MainActor
final class LoginWindowController: NSObject, NSWindowDelegate, WKHTTPCookieStoreObserver {
  enum Result: Equatable { case cookie(String, expires: Date?), cancelled, timedOut }

  private static let dataStoreID = UUID(uuidString: "6B1C8E8A-3C0B-4D4E-9C2C-0F8B8C1D2E3F")!
  private let loginURL = URL(string: "https://www.pointfree.co/login")!
  private let validate: @Sendable (String) async throws -> Bool
  private var window: NSWindow!
  private var webView: WKWebView!
  private var timeoutTimer: Timer?
  private var validating = false
  private var rejected: Set<String> = []
  private(set) var result: Result?

  init(validate: @escaping @Sendable (String) async throws -> Bool) {
    self.validate = validate
    super.init()
  }

  func run(timeout: TimeInterval) -> Result {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let config = WKWebViewConfiguration()
    config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreID)
    webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 720), configuration: config)
    config.websiteDataStore.httpCookieStore.add(self)

    window = NSWindow(
      contentRect: webView.frame,
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered, defer: false
    )
    window.title = "Sign in to Point-Free"
    window.isReleasedWhenClosed = false
    window.contentView = webView
    window.delegate = self
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate()
    webView.load(URLRequest(url: loginURL))

    timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.finish(.timedOut) }
    }
    checkCookies()  // профиль мог сохранить живую сессию с прошлого раза
    app.run()
    return result ?? .cancelled
  }

  nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    Task { @MainActor in self.checkCookies() }
  }

  private func checkCookies() {
    guard result == nil, !validating else { return }
    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self, self.result == nil, !self.validating else { return }
      guard let cookie = cookies.first(where: { $0.name == PointFreeClient.cookieName && $0.domain.hasSuffix("pointfree.co") }),
            !self.rejected.contains(cookie.value)
      else { return }
      self.validating = true
      let value = cookie.value
      let expires = cookie.expiresDate
      let validate = self.validate
      Task { @MainActor in
        let ok = (try? await validate(value)) ?? false
        self.validating = false
        if ok {
          self.finish(.cookie(value, expires: expires))
        } else {
          self.rejected.insert(value)  // анонимная сессия (например, состояние OAuth); ждём дальше
        }
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    if result == nil { finish(.cancelled) }
  }

  private func finish(_ value: Result) {
    guard result == nil else { return }
    result = value
    timeoutTimer?.invalidate()
    webView.configuration.websiteDataStore.httpCookieStore.remove(self)
    window.delegate = nil
    window.orderOut(nil)
    NSApp.stop(nil)
    // NSApp.stop срабатывает только после следующего события — шлём пустое.
    let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
    NSApp.postEvent(wake, atStart: true)
  }
}
```

- [ ] **Step 2: Команда login**

```swift
import ArgumentParser
import Dependencies
import Foundation
import PointFreeKit

struct Login: AsyncParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Sign in to pointfree.co with GitHub in a browser window.")

  @Option(help: "Save a pf_session cookie value copied from your browser instead of opening a window.")
  var cookie: String?

  @Option(help: "Seconds to wait for the login to complete.")
  var timeout: Double = 300

  @MainActor
  func run() async throws {
    do {
      try await performLogin()
    } catch let code as ExitCode {
      throw code
    } catch {
      FileHandle.standardError.write(Data("Login failed: \(error)\n".utf8))
      throw ExitCode(4)
    }
  }

  @MainActor
  private func performLogin() async throws {
    @Dependency(\.sessionStore) var store
    @Dependency(\.pointFreeClient) var client

    let value: String
    let expires: Date?
    if let cookie {
      value = cookie
      expires = nil
    } else {
      FileHandle.standardError.write(Data("Opening pointfree.co login window…\n".utf8))
      let validate = client.validateSession
      let controller = LoginWindowController(validate: { try await validate($0) })
      switch controller.run(timeout: timeout) {
      case .cookie(let v, let e): value = v; expires = e
      case .cancelled:
        FileHandle.standardError.write(Data("Login cancelled.\n".utf8))
        throw ExitCode(1)
      case .timedOut:
        FileHandle.standardError.write(Data("Login timed out.\n".utf8))
        throw ExitCode(3)
      }
    }

    guard try await client.validateSession(value) else {
      FileHandle.standardError.write(Data("pointfree.co rejected the session cookie.\n".utf8))
      throw ExitCode(2)
    }
    let now = Date()
    let session = Session(cookie: value, expiresAt: expires ?? now.addingTimeInterval(7 * 24 * 3600), savedAt: now)
    try store.save(session)
    FileHandle.standardError.write(Data("Signed in. Session saved until \(session.expiresAt).\n".utf8))
  }
}
```

Добавить `Login.self` в `subcommands` корневой команды.

- [ ] **Step 3: Ручная проверка**

Run: `swift build && .build/debug/pointfree-mcp login`
Expected: открывается окно с pointfree.co; после нажатия «Login with GitHub» окно не закрывается на промежуточной анонимной cookie, а только после реального входа; в stderr «Signed in. Session saved until …», файл `~/.pointfree-mcp/session.json` с правами `-rw-------`. `pointfree-mcp status` печатает «Signed in». Закрыть окно до входа — код выхода 1. Выключить сеть и запустить `login --cookie x` — код выхода 4.

Затем проверить платный эпизод через сервер:
```bash
(printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fetchEpisode","arguments":{"episode":"381","section":"t349"}}}'; sleep 15) \
  | .build/debug/pointfree-mcp serve
```
Expected: глава с текстом и кодом, не ошибка `loginRequired`. После `pointfree-mcp logout` тот же вызов возвращает `isError: true` с текстом про `login`.

Если окно не появляется: убедиться, что `run()` помечен `@MainActor` и вызывается на главном потоке (ArgumentParser вызывает `run()` из async `main`). Если WebKit ругается на data store — заменить `WKWebsiteDataStore(forIdentifier:)` на `.default()`.

- [ ] **Step 4: Проверка инструмента `login` из сервера**

Выполнить `pointfree-mcp logout`, затем отправить серверу `tools/call` с `{"name":"login","arguments":{}}`: должно открыться окно, после входа ответ «Signed in to pointfree.co…».

- [ ] **Step 5: Commit**

```bash
git add Sources/PointFreeMCP
git commit -m "feat: GitHub login via WKWebView window and login command"
```

---

### Task 15: Живые тесты, README и подключение к Claude Code

**Files:**
- Create: `Tests/PointFreeKitTests/LiveTests.swift`
- Create: `README.md`

- [ ] **Step 1: Живые тесты за флагом**

```swift
import Dependencies
import Foundation
import Testing
@testable import PointFreeKit

private let live = ProcessInfo.processInfo.environment["POINTFREE_LIVE"] == "1"

/// Живые зависимости: в тестовом контексте swift-dependencies без явного `.live` подставляет unimplemented-значения.
private func liveClient() -> PointFreeClient {
  withDependencies { $0.context = .live } operation: { PointFreeClient.live(cache: MemoryCache(ttl: 60, maxEntries: 5)) }
}

@Test(.enabled(if: live)) func liveSearchAndFreeEpisode() async throws {
  let client = liveClient()
  let episodes = try await client.episodes()
  #expect(episodes.count > 300)
  #expect(episodes.allSatisfy { $0.id == $0.sequence })  // fetchEpisode использует номер как id

  let html = try await client.search(SearchQuery(query: "Sendable", scope: .dialogue))
  let search = try SearchPageParser.parse(html: html, url: nil)
  #expect(!search.results.isEmpty)
  #expect(search.total ?? 0 >= search.results.count)
  #expect(search.results.contains { !$0.hits.isEmpty })

  let posts = try BlogFeedParser.parse(xml: try await client.blogFeed())
  #expect(posts.count > 200)
  let latest = try #require(posts.max { $0.number < $1.number })
  #expect(!(try BlogContentParser.blocks(html: latest.contentHTML)).isEmpty)

  let page = try EpisodePageParser.parse(html: try await client.episodePage("ep1-functions"), url: nil)
  #expect(page.transcript.chapters.count >= 5)
  #expect(!page.isTruncated)
  #expect(page.transcript.hasBody)
}

@Test(.enabled(if: live)) func liveCollections() async throws {
  let client = liveClient()
  let index = try CollectionsParser.parseIndex(html: try await client.collectionsPage())
  #expect(index.contains { $0.slug == "composable-architecture" })
  let c = try CollectionsParser.parseCollection(html: try await client.collectionPage("composable-architecture"), slug: "composable-architecture")
  #expect(c.sections.contains { $0.slug == "testing" })
  let s = try CollectionsParser.parseSection(html: try await client.sectionPage("composable-architecture", "testing"))
  #expect(s.groups.first?.episodes.contains { $0.number == 82 } == true)
}

@Test(.enabled(if: live)) func liveLockedEpisodeWithSavedSession() async throws {
  let client = liveClient()
  let page = try EpisodePageParser.parse(html: try await client.episodePage("381"), url: nil)
  let signedIn = (try? SessionStore.liveValue.load()) != nil
  #expect(page.isTruncated == !signedIn)
}
```

Run: `swift test` (живые пропущены) и `POINTFREE_LIVE=1 swift test --filter LiveTests`.
Expected: обычный прогон зелёный; живой прогон зелёный при наличии сети.

- [ ] **Step 2: README**

Содержание `README.md`: назначение; требования (macOS 26, Xcode 26, подписка Point-Free для платных эпизодов); установка:
```bash
swift build -c release
claude mcp add pointfree -- "$PWD/.build/release/pointfree-mcp" serve
```
команды `login`, `status`, `logout`; список семи инструментов с примерами вызовов; примечание про 7-дневную сессию и инструмент `login`; примечание, что поиск сайта отдаёт не больше ~50 карточек; раздел «Лицензия и контент»: код MIT, транскрипты и видео принадлежат Point-Free, блог под CC BY-NC-SA 4.0, сервер получает контент только по запросу и, для платного, по личной сессии пользователя, не кэширует на диске и не предназначен для перераспространения; кэш в памяти на 1 час.

- [ ] **Step 3: Подключить к Claude Code и проверить**

```bash
swift build -c release
claude mcp add pointfree -- "$PWD/.build/release/pointfree-mcp" serve
```
В новой сессии Claude Code: «найди в Point-Free, как тестировать эффекты в TCA» → ожидается вызов `searchPointFree`, затем `fetchEpisode` с `section`. «Что нового в LazyState 1.0?» → `listBlogPosts` с filter и `fetchBlogPost`. Проверить, что ответы приходят в markdown и что после `logout` инструмент `login` открывает окно.

- [ ] **Step 4: Commit**

```bash
git add README.md Tests/PointFreeKitTests/LiveTests.swift
git commit -m "docs: README, live tests behind POINTFREE_LIVE"
```

---

### Task 16: Полный текст поста блога со страницы

**Files:**
- Modify: `Sources/PointFreeKit/Client/PointFreeClient.swift` (добавить `blogPostPage`)
- Modify: `Sources/PointFreeKit/Parsing/BlogContentParser.swift` (выделить `blocks(in:)`, добавить `blocks(page:url:)`)
- Modify: `Sources/PointFreeKit/Tools/ToolCatalog.swift` (`fetchBlogPost` читает страницу)
- Modify: `Sources/PointFreeKit/Tools/ToolDefinitions.swift` (описание `fetchBlogPost`)
- Create: `Tests/PointFreeKitTests/Fixtures/blog-post.html`
- Modify: `Tests/PointFreeKitTests/BlogTests.swift`, `Tests/PointFreeKitTests/PointFreeClientTests.swift`, `Tests/PointFreeKitTests/ToolCatalogTests.swift`

**Interfaces:**
- Consumes: `PointFreeClient` (Task 6), `BlogContentParser.blocks(html:)` и `BlogFeedParser` (Task 11), `ToolCatalog.fetchBlogPost` (Task 12), `PointFreeError.structureChanged`.
- Produces: `PointFreeClient.blogPostPage: @Sendable (_ pathComponent: String) async throws -> String`; `BlogContentParser.blocks(in element: Element) throws -> [Transcript.Block]`; `BlogContentParser.blocks(page html: String, url: URL?) throws -> [Transcript.Block]`.

Причина: Atom-фид содержит только анонс (один абзац) каждого поста, а не полный текст (проверено на живом фиде: ни одной записи с `<pre>`, максимум 788 байт на запись). Полный текст лежит на странице `/blog/posts/{slug}` (и `/blog/posts/{number}`, отдаётся 200 без редиректа) внутри `article > pf-markdown > pf-vstack` с теми же блоками, что и транскрипт (`p`, `pre > code`, `h2`–`h4`, `ul/ol > li`, `blockquote`). Фид остаётся источником списка (номер, название, дата, ссылка).

- [ ] **Step 1: Фикстура `blog-post.html`**

```html
<!doctype html><html><head><title>LazyState 1.0: Now available to everyone</title></head><body>
<h3>LazyState 1.0: Now available to everyone</h3>
<p>Monday September 14, 2026</p>
<article><pf-markdown><pf-vstack>
  <p>We are excited to announce <a href="https://github.com/pointfreeco/swiftui-lazy-state">LazyState</a> <strong>1.0</strong>.</p>
  <h2>Usage</h2>
  <pre><code>@LazyState var model = Model()
</code></pre>
  <ul><li>One</li><li>Two with <code>code</code></li></ul>
  <blockquote><p>Quoted.</p></blockquote>
</pf-vstack></pf-markdown></article>
<footer><p>Footer must not appear.</p></footer>
</body></html>
```

- [ ] **Step 2: Тесты**

В `BlogTests.swift` добавить:
```swift
@Test func parsesBlogPostPageArticle() throws {
  let blocks = try BlogContentParser.blocks(page: fixtureString("blog-post.html"), url: nil)
  #expect(blocks == [
    .paragraph("We are excited to announce [LazyState](https://github.com/pointfreeco/swiftui-lazy-state) **1.0**."),
    .heading("Usage"),
    .code("@LazyState var model = Model()\n"),
    .listItem("One"),
    .listItem("Two with `code`"),
    .quote("Quoted."),
  ])
}

@Test func blogPageWithoutArticleIsStructureChange() {
  #expect(throws: PointFreeError.structureChanged("article", nil)) {
    _ = try BlogContentParser.blocks(page: "<html><body><p>nope</p></body></html>", url: nil)
  }
}
```

В `PointFreeClientTests.swift` добавить:
```swift
@Test func blogPostPageIsFetchedWithoutCookieAndCached() async throws {
  let log = RequestLog()
  let session = Session(cookie: "COOKIE", expiresAt: Date(timeIntervalSince1970: 5_000), savedAt: Date(timeIntervalSince1970: 0))
  let c = client(session: session, log: log) { _ in HTTPResponse(statusCode: 200, body: Data("<html><article></article></html>".utf8)) }
  _ = try await c.blogPostPage("228-lazystate-1-0-now-available-to-everyone")
  _ = try await c.blogPostPage("228-lazystate-1-0-now-available-to-everyone")
  #expect(log.requests.count == 1)
  #expect(log.requests[0].url?.absoluteString == "https://www.pointfree.co/blog/posts/228-lazystate-1-0-now-available-to-everyone")
  #expect(log.requests[0].value(forHTTPHeaderField: "Cookie") == nil)
}
```

В `ToolCatalogTests.swift` заменить тест `blogToolsListAndFetchFromFeed` на:
```swift
@Test func blogToolsListFromFeedAndFetchFromPage() async throws {
  let catalog = ToolCatalog()
  let list = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
  } operation: { await catalog.call(name: "listBlogPosts", arguments: try args(#"{"filter":"lazystate","limit":5}"#)) }
  #expect(!list.isError)
  #expect(list.text.contains("#228 LazyState 1.0"))
  #expect(!list.text.contains("#1 Announcing"))

  let post = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
    $0.pointFreeClient.blogPostPage = { path in
      #expect(path == "228-lazystate-1-0-now-available-to-everyone")
      return try fixtureString("blog-post.html")
    }
  } operation: { await catalog.call(name: "fetchBlogPost", arguments: try args(#"{"post":"228"}"#)) }
  #expect(!post.isError)
  #expect(post.text.hasPrefix("# LazyState 1.0: Now available to everyone"))
  #expect(post.text.contains("```swift\n@LazyState var model = Model()\n```"))
  #expect(post.text.contains("- Published: 2026-09-14"))

  let missing = try await withDependencies {
    $0.pointFreeClient.blogFeed = { try fixtureString("blog-atom.xml") }
  } operation: { await catalog.call(name: "fetchBlogPost", arguments: try args(#"{"post":"999"}"#)) }
  #expect(missing.isError)
  #expect(missing.text.contains("999"))
}
```

- [ ] **Step 3: Запустить — не компилируется / падает**

Run: `swift test --filter "BlogTests|PointFreeClientTests|ToolCatalogTests"`
Expected: ошибки компиляции (`blogPostPage`, `blocks(page:url:)` не определены).

- [ ] **Step 4: Реализация**

`PointFreeClient.swift`: поле `public var blogPostPage: @Sendable (_ pathComponent: String) async throws -> String` (после `blogFeed`); в `live(cache:)`:
```swift
      blogPostPage: { pathComponent in
        try await cachedHTML(key: "blog/posts/\(pathComponent)") { try await get("blog/posts/\(pathComponent)", cookie: nil) }
      },
```

`BlogContentParser.swift`:
```swift
public enum BlogContentParser {
  /// HTML-фрагмент (например, из Atom-фида).
  public static func blocks(html: String) throws -> [Transcript.Block] {
    let doc = try SwiftSoup.parseBodyFragment(html)
    guard let body = doc.body() else { return [] }
    return try blocks(in: body)
  }

  /// Полная страница поста: тело — `article`.
  public static func blocks(page html: String, url: URL?) throws -> [Transcript.Block] {
    let doc = try SwiftSoup.parse(html)
    guard let article = try doc.select("article").first() else {
      throw PointFreeError.structureChanged("article", url)
    }
    return try blocks(in: article)
  }

  public static func blocks(in root: Element) throws -> [Transcript.Block] {
    // существующий цикл по root.select("h1, h2, h3, h4, h5, h6, p, pre, li, blockquote") без изменений
  }
}
```

`ToolCatalog.fetchBlogPost`:
```swift
  func fetchBlogPost(_ args: ToolArguments) async throws -> ToolOutput {
    guard let raw = args.string("post") else { throw PointFreeError.invalidArgument("`post` is required") }
    guard let ref = BlogPostRef.parse(raw) else {
      throw PointFreeError.invalidArgument("`post` must be a number (228), a slug (228-…) or a pointfree.co blog URL; got \"\(raw)\"")
    }
    let posts = try BlogFeedParser.parse(xml: try await client.blogFeed())
    guard let post = posts.first(where: { $0.number == ref.number }) else {
      throw PointFreeError.invalidArgument("Blog post \(ref.number) not found in the feed")
    }
    let html = try await client.blogPostPage(post.slug)
    let blocks = try BlogContentParser.blocks(page: html, url: post.url)
    return ToolOutput(text: MarkdownRenderer.blogPost(post, blocks: blocks))
  }
```

`ToolDefinitions.swift`: описание `fetchBlogPost` заменить на: "Fetch a Point-Free Pointers blog post as markdown with code blocks (full text from the post page). Accepts a post number (228), slug (228-lazystate-1-0-now-available-to-everyone) or URL. No login needed."

- [ ] **Step 5: Тесты проходят**

Run: `swift test --filter "BlogTests|PointFreeClientTests|ToolCatalogTests"`, затем полный `swift test`.
Expected: PASS, без предупреждений.

- [ ] **Step 6: Живая проверка**

```bash
swift build && (printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fetchBlogPost","arguments":{"post":"228"}}}'; sleep 15) \
  | .build/debug/pointfree-mcp serve
```
Expected: markdown поста с несколькими блоками ```swift (на живой странице 6 `<pre>`).

- [ ] **Step 7: Commit**

```bash
git add Sources/PointFreeKit Tests/PointFreeKitTests
git commit -m "feat: fetch full blog post text from the post page" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 17: Гигиена по замечаниям swift-server-lint

**Files:**
- Modify: `Sources/PointFreeKit/Client/PointFreeClient.swift`, `Sources/PointFreeKit/Client/SearchQuery.swift`, `Sources/PointFreeKit/Models/Episode.swift`, `Sources/PointFreeKit/Models/EpisodeRef.swift`, `Sources/PointFreeKit/Tools/ToolArguments.swift`, `Sources/PointFreeKit/Tools/ToolCatalog.swift`, `Sources/PointFreeMCP/Commands/Serve.swift`, `Sources/PointFreeMCP/LoginWindow/LoginWindowController.swift`
- Modify: `Tests/PointFreeKitTests/EpisodeDecodingTests.swift`, `EpisodePageParserTests.swift`, `MarkdownRendererTests.swift`, `MemoryCacheTests.swift`, `PointFreeClientTests.swift`, `ToolCatalogTests.swift`

**Interfaces:** публичные сигнатуры не меняются; поведение не меняется; все 61 тест проходят без изменений ожиданий.

В проекте у владельца стоит PostToolUse-хук `swift-server-lint`. Часть его правил к этому пакету не относится (`foundation-avoidance`, `postgres.sql-injection` на интерполяции markdown, `cyclomatic-complexity` парсеров), они остаются как есть и объясняются в README (Task 15). Исправляются только содержательные замечания:

- [ ] **Step 1: Force unwrap → безопасные конструкции**

  - `PointFreeClient.swift`: `baseURL` — оставить как `URL(string:)!` нельзя по правилу; заменить на `static let baseURL: URL = { guard let url = URL(string: "https://www.pointfree.co") else { preconditionFailure("invalid base URL") }; return url }()`. Аналогично `URLComponents(url:resolvingAgainstBaseURL:)!` и `components.url!` в `get` — через `guard let … else { throw PointFreeError.network("invalid URL for \(path)") }`.
  - `SearchQuery.swift`: `URLComponents(...)!` и `components.url!` — `guard let`, с `preconditionFailure` (URL строится из константы и корректных query items; это инвариант программы).
  - `Episode.swift`: `pageURL` — `URL(string:)!` → та же схема с `preconditionFailure` (число в пути всегда валидно).
  - `LoginWindowController.swift`: `UUID(uuidString:)!` и `URL(string:)!` — константы, вычислить через замыкание с `preconditionFailure`; `NSEvent.otherEvent(...)!` — `if let wake = … { NSApp.postEvent(wake, atStart: true) }`; `window`/`webView` как IUO → обычные optional с `guard let` в местах использования (или инициализировать в `init` и сделать `let`; предпочесть `let`, создавая окно и webView в `init`, а показывать в `run`).
  - Тесты: `TimeZone(identifier: "UTC")!` → `try #require(TimeZone(identifier: "UTC"))`; `URL(string: …)!` в тестах → `try #require(URL(string: …))` (функции тестов уже `throws` или сделать `throws`).

- [ ] **Step 2: `@unchecked Sendable` с комментарием SAFETY**

  В `MemoryCacheTests.swift`, `PointFreeClientTests.swift`, `ToolCatalogTests.swift` над каждым `@unchecked Sendable` классом добавить строку `// SAFETY: тест обращается к объекту последовательно из одного таска; синхронизация не нужна.` В `ToolCatalogTests.swift` три одинаковых `Flag` заменить одним приватным `final class Flag: @unchecked Sendable { var value = false }` на уровне файла (с тем же комментарием) и использовать поле `value`.

- [ ] **Step 3: Неиспользуемые импорты**

  Удалить `import Foundation` там, где хук отмечает и компилятор не требует: `EpisodeRef.swift` (используются `trimmingCharacters`, значит Foundation нужен — оставить и проверить сборкой), `ToolArguments.swift`, `ToolCatalog.swift`, `Serve.swift`, `EpisodeDecodingTests.swift`, `EpisodePageParserTests.swift`. Правило: убрать, собрать; если сборка падает — вернуть.

- [ ] **Step 4: Сборка, тесты, хук**

  Run: `swift build && swift test`
  Expected: 0 предупреждений компилятора, 61 тест PASS. Затем `~/.claude/hooks/swift-server-lint.sh` (если запускается вручную) не должен показывать `force-unwrap`, `implicitly-unwrapped-optional`, `unchecked-sendable` и `unused-import`; остаются только `cyclomatic-complexity`, `foundation-avoidance` и `postgres.sql-injection`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "chore: remove force unwraps, document unchecked Sendable, drop unused imports" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage.** Инструменты: `searchPointFree` с учётом обрезки до ~50 карточек (Task 8, 10, 12), `fetchEpisode` с `section` и ошибками входа (Task 7, 10, 12), `listEpisodes` (Task 2, 10, 12), `fetchCollection` с `slug`/`section` (Task 9, 10, 12), `listBlogPosts` и `fetchBlogPost` через Atom-фид (Task 6, 10, 11, 12), `login` (Task 12, 14). Авторизация через WKWebView, файл 0600, `--cookie`, `logout`, `status` (Task 4, 13, 14). Сеть: User-Agent, таймаут, без редиректов, cookie только для pointfree.co (Task 4, 6). Кэш в памяти, лимит 50, единый TTL 1 ч (Task 5, 6). Разбор HTML по семантике, терпимость к `blockquote` и вложенным заголовкам, `structureChanged` (Task 7–9, 11). Таблица ошибок (Task 4, 12). Тесты на синтетических фикстурах и живые за флагом (Task 15). Лицензионные ограничения: фикстуры синтетические, `live/` в `.gitignore`, транскрипты не пишутся на диск.

**Порядок задач.** Task 11 (блог) идёт до Task 10 (рендер) и Task 12 (инструменты), потому что рендер и каталог ссылаются на типы блога; остальные задачи в порядке номеров. См. «Execution Order» в шапке.

**Type consistency.** `PointFreeClient` поля (включая `blogFeed`) совпадают между Task 6 и 12; `SearchPage` из Task 8 используется в Task 10 и 12; `Transcript.Block` с `.quote`/`.heading` из Task 7 используется в Task 10 и 11; `EpisodePage.isTruncated`, `Transcript.hasBody`, `Transcript.chapter(matching:)` используются в Task 10 и 12 как определены в Task 7; `BlogPost`, `BlogPostRef`, `BlogFeedParser`, `BlogContentParser` из Task 11 используются в Task 10 и 12; `ToolArguments.string/int/bool` и `ToolOutput` совпадают между Task 12 и 13; `LoginOutcome` совпадает между `LoginLauncher` и `ToolCatalog.login`; коды выхода `Login` (0/1/2/3) согласованы с `LoginLauncher.liveValue` (1 → cancelled, прочие → failed).

**Review Focus.** Пункт 1 — Task 3; 2 и 3 — Task 6; 4 — Task 7 (сущности и вложенный `span` в `<pre>`); 5 — Task 12 (`fetchEpisodeWithValidSessionButTruncatedKeepsSession`).
