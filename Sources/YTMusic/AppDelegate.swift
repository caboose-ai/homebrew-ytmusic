import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    static let homeURL = URL(string: "https://music.youtube.com")!

    // Google sign-in rejects embedded webviews unless the UA looks like desktop Safari.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private static let inAppDomains = [
        "youtube.com", "google.com", "gstatic.com", "googleusercontent.com", "ytimg.com", "googlevideo.com",
    ]

    private let player = PlayerBridge()
    private var window: NSWindow!
    private var webView: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(
            WKUserScript(source: PlayerBridge.userScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.add(player, name: PlayerBridge.messageHandlerName)

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        player.webView = webView

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YT Music"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.center()
        // Restores the saved frame if one exists, so this must come after center().
        window.setFrameAutosaveName("MainWindow")

        showMainWindow(nil)
        webView.load(URLRequest(url: Self.homeURL))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow(nil)
        }
        return true
    }

    // Closing hides the window; the page keeps playing and the Dock icon brings it back.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - Menu actions

    @objc func showMainWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func reloadPage(_ sender: Any?) {
        webView.reload()
    }

    @objc func goBack(_ sender: Any?) {
        webView.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        webView.goForward()
    }

    @objc func goHome(_ sender: Any?) {
        webView.load(URLRequest(url: Self.homeURL))
    }

    @objc func togglePlayPause(_ sender: Any?) {
        player.send(.toggle)
    }

    @objc func nextTrack(_ sender: Any?) {
        player.send(.next)
    }

    @objc func previousTrack(_ sender: Any?) {
        player.send(.previous)
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame ?? true, let url = navigationAction.request.url,
              Self.isExternal(url, linkClick: navigationAction.navigationType == .linkActivated) else {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - WKUIDelegate

    // target=_blank: stay in the wrapper for our own hosts, otherwise hand off to the browser.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if Self.isInApp(url) {
            webView.load(navigationAction.request)
        } else {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    // Only web URLs are judged by host. about:, blob: and data: are the page's own content,
    // and other schemes (mailto:) leave the app only when they were clicked.
    private static func isExternal(_ url: URL, linkClick: Bool) -> Bool {
        switch url.scheme?.lowercased() ?? "" {
        case "https", "http":
            return !isInApp(url)
        case "about", "blob", "data":
            return false
        default:
            return linkClick
        }
    }

    private static func isInApp(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return false
        }
        if inAppDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return true
        }
        // google.com plus its country domains (google.de, google.co.uk, google.com.au).
        // Anchored so that google.example.com or google.zip do not qualify.
        return host.range(of: #"^(?:[a-z0-9-]+\.)*google\.(?:com|(?:com?\.)?[a-z]{2})$"#, options: .regularExpression) != nil
    }
}
