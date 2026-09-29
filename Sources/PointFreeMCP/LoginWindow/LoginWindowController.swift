import AppKit
import Foundation
import PointFreeKit
import WebKit

@MainActor
final class LoginWindowController: NSObject, NSApplicationDelegate, NSWindowDelegate, WKHTTPCookieStoreObserver,
  WKNavigationDelegate
{
  enum Result: Equatable { case cookie(String, expires: Date?), cancelled, timedOut }

  private static let dataStoreID: UUID = {
    guard let id = UUID(uuidString: "6B1C8E8A-3C0B-4D4E-9C2C-0F8B8C1D2E3F") else { preconditionFailure("invalid data store ID") }
    return id
  }()
  private let loginURL: URL = {
    guard let url = URL(string: "https://www.pointfree.co/login") else { preconditionFailure("invalid login URL") }
    return url
  }()
  private let validate: @Sendable (String) async throws -> Bool
  private var window: NSWindow?
  private var webView: WKWebView?
  private var timeoutTimer: Timer?
  private var pollTimer: Timer?
  private var cookieStore: WKHTTPCookieStore?  // WebKit не удерживает наблюдателей; прокси хранилища должен жить
  private var validating = false
  private var rejected: Set<String> = []
  private var loggedCookieNames: Set<String>?  // список имён пишем в stderr только при изменении
  private(set) var result: Result?

  private func log(_ message: String) {
    FileHandle.standardError.write(Data("login: \(message)\n".utf8))
  }

  /// Только host + path: query/fragment (например, одноразовые `code`/`state` OAuth) в лог не попадают.
  private func redacted(_ url: URL?) -> String {
    guard let url else { return "-" }
    return (url.host() ?? "") + url.path()
  }

  init(validate: @escaping @Sendable (String) async throws -> Bool) {
    self.validate = validate
    super.init()
  }

  func run(timeout: TimeInterval) -> Result {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.delegate = self  // Quit из Dock/переключателя = отмена (см. applicationShouldTerminate); NSApp.delegate — weak

    let config = WKWebViewConfiguration()
    config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreID)
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 720), configuration: config)
    self.webView = webView
    webView.navigationDelegate = self
    let store = webView.configuration.websiteDataStore.httpCookieStore
    cookieStore = store
    store.add(self)

    let window = NSWindow(
      contentRect: webView.frame,
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered, defer: false
    )
    window.title = "Sign in to Point-Free"
    window.isReleasedWhenClosed = false
    window.contentView = webView
    window.delegate = self
    self.window = window
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    app.activate()
    log("opening \(redacted(loginURL))")
    webView.load(URLRequest(url: loginURL))

    pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkCookies() }
    }
    timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
      // Не Task { @MainActor }: NSApp.run() крутится на главном потоке прямо из синхронного EntryPoint.main(),
      // до dispatchMain(), поэтому главная очередь (executor главного актора) до выхода из run() не обслуживается.
      MainActor.assumeIsolated { self?.finish(.timedOut) }
    }
    checkCookies()  // профиль мог сохранить живую сессию с прошлого раза
    installMainMenu(app)
    app.run()
    app.delegate = nil
    return result ?? .cancelled
  }

  /// Без главного меню не работают ⌘Q и стандартные сочетания правки (⌘C/⌘V в полях пароля и 2FA).
  /// Quit идёт через `terminate(_:)` → `applicationShouldTerminate` → отмена (код 1).
  private func installMainMenu(_ app: NSApplication) {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit pointfree-mcp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    // Действия идут по цепочке ответчиков (target nil) до WKWebView; undo:/redo: — без публичного объявления в Swift.
    editMenu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    app.mainMenu = mainMenu
  }

  nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    FileHandle.standardError.write(Data("login: cookies changed\n".utf8))
    RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { self.checkCookies() } }
  }

  private func checkCookies() {
    guard result == nil, !validating else { return }
    guard let store = cookieStore ?? webView?.configuration.websiteDataStore.httpCookieStore else { return }
    store.getAllCookies { [weak self] cookies in
      guard let self, self.result == nil, !self.validating else { return }
      let names = Set(cookies.map { "\($0.name)@\($0.domain)" })
      if names != self.loggedCookieNames {
        self.loggedCookieNames = names
        self.log("cookie store has \(cookies.count) cookies: \(names.sorted().joined(separator: ", "))")
      }
      guard let cookie = cookies.first(where: {
        $0.name == PointFreeClient.cookieName
          && ($0.domain == "www.pointfree.co" || $0.domain == "pointfree.co" || $0.domain.hasSuffix(".pointfree.co"))
          && !self.rejected.contains($0.value)
      }) else { return }
      self.validating = true
      self.log("pf_session candidate (domain=\(cookie.domain)) validating")
      let value = cookie.value
      let expires = cookie.expiresDate
      let validate = self.validate
      // Валидация идёт вне главного актора; результат возвращаем через RunLoop (см. комментарий у таймера).
      Task.detached {
        var outcome: Bool?  // nil — ошибка (сеть), не приговор cookie
        var errorText = ""
        do { outcome = try await validate(value) } catch { errorText = error.localizedDescription }
        let failure = errorText
        RunLoop.main.perform(inModes: [.common]) {
          MainActor.assumeIsolated {
            self.validating = false
            switch outcome {
            case .some(true):
              self.log("pf_session accepted")
              self.finish(.cookie(value, expires: expires))
            case .some(false):
              self.log("pf_session rejected by pointfree.co")
              self.rejected.insert(value)  // анонимная сессия (например, состояние OAuth); ждём дальше
              self.checkCookies()  // за время проверки могла прийти другая cookie
            case .none:
              // Временная ошибка: не запоминаем как отвергнутую, повторяем через 2 с (границу задаёт --timeout).
              self.log("validation error: \(failure), retrying in 2 s")
              Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkCookies() }
              }
            }
          }
        }
      }
    }
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    log("didStartProvisionalNavigation \(redacted(webView.url))")
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    log("didFinish \(redacted(webView.url))")
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    log("didFailProvisionalNavigation \(redacted(webView.url ?? loginURL)): \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    log("didFail \(redacted(webView.url)): \(error.localizedDescription)")
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    log("web content process terminated")
    webView.reload()
  }

  /// Quit из Dock/переключателя приложений (или Apple event quit) иначе завершил бы процесс с кодом 0 без сессии.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    finish(.cancelled)
    return .terminateCancel
  }

  func windowWillClose(_ notification: Notification) {
    if result == nil { finish(.cancelled) }
  }

  private func finish(_ value: Result) {
    guard result == nil else { return }
    result = value
    timeoutTimer?.invalidate()
    pollTimer?.invalidate()
    cookieStore?.remove(self)
    window?.delegate = nil
    window?.orderOut(nil)
    NSApp.stop(nil)
    // NSApp.stop срабатывает только после следующего события — шлём пустое.
    if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
      NSApp.postEvent(wake, atStart: true)
    }
  }
}
