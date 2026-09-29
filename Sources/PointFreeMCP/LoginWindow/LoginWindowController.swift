import AppKit
import Foundation
import PointFreeKit
import WebKit

@MainActor
final class LoginWindowController: NSObject, NSWindowDelegate, WKHTTPCookieStoreObserver, WKNavigationDelegate {
  enum Result: Equatable { case cookie(String, expires: Date?), cancelled, timedOut }

  private static let dataStoreID = UUID(uuidString: "6B1C8E8A-3C0B-4D4E-9C2C-0F8B8C1D2E3F")!
  private let loginURL = URL(string: "https://www.pointfree.co/login")!
  private let validate: @Sendable (String) async throws -> Bool
  private var window: NSWindow!
  private var webView: WKWebView!
  private var timeoutTimer: Timer?
  private var pollTimer: Timer?
  private var cookieStore: WKHTTPCookieStore?  // WebKit не удерживает наблюдателей; прокси хранилища должен жить
  private var validating = false
  private var rejected: Set<String> = []
  private(set) var result: Result?

  private func log(_ message: String) {
    FileHandle.standardError.write(Data("login: \(message)\n".utf8))
  }

  init(validate: @escaping @Sendable (String) async throws -> Bool) {
    self.validate = validate
    super.init()
  }

  func run(timeout: TimeInterval) -> Result {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let config = WKWebViewConfiguration()
    config.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreID)
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 720), configuration: config)
    webView.navigationDelegate = self
    let store = webView.configuration.websiteDataStore.httpCookieStore
    cookieStore = store
    store.add(self)

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
    window.orderFrontRegardless()
    app.activate()
    log("opening \(loginURL.absoluteString)")
    webView.load(URLRequest(url: loginURL))

    pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkCookies() }
    }
    timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
      // Не Task { @MainActor }: пока крутится NSApp.run() внутри main-actor задачи, executor главного актора не обслуживается.
      MainActor.assumeIsolated { self?.finish(.timedOut) }
    }
    checkCookies()  // профиль мог сохранить живую сессию с прошлого раза
    app.run()
    return result ?? .cancelled
  }

  nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    FileHandle.standardError.write(Data("login: cookies changed\n".utf8))
    RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { self.checkCookies() } }
  }

  private func checkCookies() {
    guard result == nil, !validating else { return }
    (cookieStore ?? webView.configuration.websiteDataStore.httpCookieStore).getAllCookies { [weak self] cookies in
      guard let self, self.result == nil, !self.validating else { return }
      let shared = HTTPCookieStorage.shared.cookies?.count ?? 0
      let list = cookies.map { "\($0.name)@\($0.domain)" }.joined(separator: ", ")
      self.log("cookie store has \(cookies.count) cookies (HTTPCookieStorage.shared: \(shared)); \(list)")
      guard let cookie = cookies.first(where: {
        $0.name == PointFreeClient.cookieName
          && ($0.domain == "www.pointfree.co" || $0.domain == "pointfree.co" || $0.domain.hasSuffix(".pointfree.co"))
          && !self.rejected.contains($0.value)
      }) else {
        self.log("no new pf_session candidate")
        return
      }
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
    log("didStartProvisionalNavigation \(webView.url?.absoluteString ?? "-")")
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    log("didFinish \(webView.url?.absoluteString ?? "-")")
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    log("didFailProvisionalNavigation \(webView.url?.absoluteString ?? loginURL.absoluteString): \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    log("didFail \(webView.url?.absoluteString ?? "-"): \(error.localizedDescription)")
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    log("web content process terminated")
    webView.reload()
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
    window.delegate = nil
    window.orderOut(nil)
    NSApp.stop(nil)
    // NSApp.stop срабатывает только после следующего события — шлём пустое.
    let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
    NSApp.postEvent(wake, atStart: true)
  }
}
