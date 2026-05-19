import WebKit
import AppKit

enum ClaudeUsageResult {
    case ok(fiveHour: LimitWindow, weekly: LimitWindow)
    case loggedOut
    case error(String)
}

/// Hosts a WKWebView signed into claude.ai and reads the real usage limits
/// from claude.ai's own API. The user signs in once in the window; the session
/// persists across launches.
final class ClaudeWebSession: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private var webView: WKWebView!
    private var window: NSWindow!
    private var hasLoaded = false
    private var fetchInFlight = false
    private var loginPollTimer: Timer?
    private var popupWindows: [NSWindow] = []

    // Present as real Safari — Google blocks OAuth from webviews whose UA
    // lacks the Version/Safari tokens.
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    /// Called with every usage fetch result.
    var onResult: ((ClaudeUsageResult) -> Void)?

    override init() {
        super.init()
        webView = makeWebView(width: 460, height: 680)
        window = NSWindow(contentRect: webView.frame,
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Claude.ai 로그인"
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        webView.load(URLRequest(url: URL(string: "https://claude.ai/")!))
    }

    private func makeWebView(width: CGFloat, height: CGFloat,
                             configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let config = configuration ?? {
            let c = WKWebViewConfiguration()
            c.websiteDataStore = .default()        // persistent — login survives restarts
            return c
        }()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height),
                           configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = userAgent
        return wv
    }

    /// Brings up the sign-in window and polls quickly so it self-closes on login.
    func showLoginWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        loginPollTimer?.invalidate()
        loginPollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
    }

    private func stopLoginPoll() {
        loginPollTimer?.invalidate()
        loginPollTimer = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopLoginPoll()
    }

    /// Fetches real usage and reports via `onResult`. Hides the login window on success.
    func refreshUsage() {
        guard hasLoaded, (webView.url?.host ?? "").contains("claude.ai"), !fetchInFlight else { return }
        fetchInFlight = true
        var finished = false
        let finish: (ClaudeUsageResult) -> Void = { [weak self] result in
            guard let self = self, !finished else { return }
            finished = true
            self.fetchInFlight = false
            if case .ok = result {
                if self.window.isVisible { self.window.orderOut(nil) }
                self.stopLoginPoll()
            }
            self.onResult?(result)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { finish(.error("timeout")) }

        let js = #"""
        const H = {'anthropic-client-platform':'web_claude_ai','anthropic-client-version':'1.0.0','Accept':'application/json'};
        try {
          const o = await fetch('/api/organizations', {credentials:'include', headers:H, cache:'no-store'});
          if (o.status === 401 || o.status === 403) return JSON.stringify({state:'loggedOut'});
          if (!o.ok) return JSON.stringify({state:'error', detail:'orgs ' + o.status});
          const orgs = await o.json();
          for (const org of (orgs || [])) {
            const u = await fetch('/api/organizations/' + org.uuid + '/usage', {credentials:'include', headers:H, cache:'no-store'});
            if (u.ok) { const j = await u.json(); if (j && j.five_hour) return JSON.stringify({state:'ok', usage:j}); }
          }
          return JSON.stringify({state:'error', detail:'no usage'});
        } catch (e) { return JSON.stringify({state:'error', detail:String(e)}); }
        """#

        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .failure(let error):
                finish(.error(error.localizedDescription))
            case .success(let value):
                guard let string = value as? String,
                      let data = string.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let state = obj["state"] as? String else {
                    finish(.error("parse")); return
                }
                switch state {
                case "loggedOut":
                    finish(.loggedOut)
                case "ok":
                    if let usage = obj["usage"] as? [String: Any],
                       let windows = ClaudeWebSession.parse(usage) {
                        finish(.ok(fiveHour: windows.0, weekly: windows.1))
                    } else {
                        finish(.error("usage parse"))
                    }
                default:
                    finish(.error((obj["detail"] as? String) ?? "error"))
                }
            }
        }
    }

    private static func parse(_ usage: [String: Any]) -> (LimitWindow, LimitWindow)? {
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        func window(_ key: String, _ kind: WindowKind) -> LimitWindow? {
            guard let w = usage[key] as? [String: Any],
                  let util = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            var reset: Date?
            if let s = w["resets_at"] as? String {
                reset = isoFractional.date(from: s) ?? isoPlain.date(from: s)
            }
            return LimitWindow(kind: kind, usedPercent: util, resetsAt: reset, isReal: true)
        }
        guard let five = window("five_hour", .fiveHour),
              let week = window("seven_day", .weekly) else { return nil }
        return (five, week)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoaded = true
    }

    // MARK: - WKUIDelegate (OAuth popups, e.g. "Continue with Google")

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Open the popup in its own window so OAuth flows can complete.
        let popup = makeWebView(width: 500, height: 640, configuration: configuration)
        let popupWindow = NSWindow(contentRect: popup.frame,
                                   styleMask: [.titled, .closable, .resizable],
                                   backing: .buffered, defer: false)
        popupWindow.title = "로그인"
        popupWindow.contentView = popup
        popupWindow.isReleasedWhenClosed = false
        popupWindow.center()
        popupWindow.makeKeyAndOrderFront(nil)
        popupWindows.append(popupWindow)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let win = popupWindows.first(where: { $0.contentView === webView }) {
            win.orderOut(nil)
            popupWindows.removeAll { $0 === win }
        }
    }
}
