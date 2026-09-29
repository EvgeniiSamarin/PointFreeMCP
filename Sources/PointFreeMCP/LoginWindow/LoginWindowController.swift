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
      // Не Task { @MainActor }: пока крутится NSApp.run() внутри main-actor задачи, executor главного актора не обслуживается.
      MainActor.assumeIsolated { self?.finish(.timedOut) }
    }
    checkCookies()  // профиль мог сохранить живую сессию с прошлого раза
    app.run()
    return result ?? .cancelled
  }

  nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { self.checkCookies() } }
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
      // Валидация идёт вне главного актора; результат возвращаем через RunLoop (см. комментарий у таймера).
      Task.detached {
        let ok = (try? await validate(value)) ?? false
        RunLoop.main.perform(inModes: [.common]) {
          MainActor.assumeIsolated {
            self.validating = false
            if ok {
              self.finish(.cookie(value, expires: expires))
            } else {
              self.rejected.insert(value)  // анонимная сессия (например, состояние OAuth); ждём дальше
            }
          }
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
