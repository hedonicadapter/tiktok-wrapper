import SwiftUI
import WebKit

/// Loads an arbitrary URL (Anki web, Duolingo, your own page). Unlocks after a timer.
/// Shares the default cookie store so logins on those sites persist.
struct WebInterruptView: View {
    let url: URL
    let unlockAfterSeconds: Int
    let hideSelectors: [String]
    let onComplete: (InterruptResult) -> Void

    @State private var remaining: Int

    init(url: URL, unlockAfterSeconds: Int, hideSelectors: [String] = [],
         onComplete: @escaping (InterruptResult) -> Void) {
        self.url = url
        self.unlockAfterSeconds = unlockAfterSeconds
        self.hideSelectors = hideSelectors
        self.onComplete = onComplete
        _remaining = State(initialValue: unlockAfterSeconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlainWebView(url: url, hideSelectors: hideSelectors)
            UnlockButton(title: remaining > 0 ? "Unlocks in \(remaining)s" : "Done", enabled: remaining <= 0) {
                onComplete(.done)
            }
        }
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
            }
        }
    }
}

struct PlainWebView: UIViewRepresentable {
    let url: URL
    var hideSelectors: [String] = []

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        if !hideSelectors.isEmpty,
           let data = try? JSONEncoder().encode(hideSelectors),
           let json = String(data: data, encoding: .utf8) {
            // Per-pack hide list (manifest.hideSelectors)
            let js = """
            (function(){var s=document.createElement('style');
            s.textContent=\(json).join(',')+'{display:none !important}';
            (document.head||document.documentElement).appendChild(s);})();
            """
            cfg.userContentController.addUserScript(
                WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
