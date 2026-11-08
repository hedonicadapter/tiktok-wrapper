import SwiftUI
import WebKit

struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDebug = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .topTrailing) {
                // Inside the safe area: the page's viewport is exactly what's visible (no content
                // insets pushing it under the status bar or off the bottom).
                TikTokWebView(model: model)

                // Off the feed (profile, video page, settings): native way back.
                if !model.isOnFeed && model.phase == .hidden {
                    Button { model.goBackOrFeed() } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 52)
                    .zIndex(1.5)
                }

                // Armed: invisible shield catches the next swipe so TikTok never sees it.
                if model.phase == .armed {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(armedDrag(height: h))
                }

                // The card. Lives in the same ZStack, slides vertically like a feed item.
                if let card = model.card, model.phase != .hidden {
                    FeedCard(card: card, phase: model.phase) { result in
                        model.cardCompleted(result)
                    }
                    .frame(width: geo.size.width, height: h)
                    .offset(y: cardOffset(height: h))
                    .gesture(dismissDrag(height: h), including: isCompleted ? .all : .subviews)
                    .transition(.identity)
                    .zIndex(1)
                }

                if model.scheduler.config.showDebug {
                    debugBadge.zIndex(2)
                }
            }
        }
        .ignoresSafeArea()   // geo = full screen, so the card covers the whole feed
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(item: $model.popup) { popup in
            PopupWebView(popup: popup) { model.popup = nil }
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { model.reload() }
            if model.phase != .hidden && model.phase != .armed { model.pauseFeed() }
        }
    }

    private var isCompleted: Bool {
        if case .completed = model.phase { return true }
        return false
    }

    // MARK: Card geometry

    private func cardOffset(height h: CGFloat) -> CGFloat {
        switch model.phase {
        case .hidden: return h
        case .armed: return max(0, h + model.dragOffset)          // dragging up from below
        case .shown: return 0
        case .completed: return model.dragOffset                  // follows the finger either way
        case .dismissing: return model.dismissUp ? -h : h
        }
    }

    /// Swipe up while armed drags the card in. Commit past 20% or on a flick.
    private func armedDrag(height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                model.dragOffset = min(0, v.translation.height)
            }
            .onEnded { v in
                let commit = -v.translation.height > h * 0.2 || -v.predictedEndTranslation.height > h * 0.5
                withAnimation(.spring(duration: 0.35, bounce: 0)) {
                    if commit { model.showCard() } else { model.dragOffset = 0 }
                }
            }
    }

    /// After unlock, a swipe up or down dismisses the card and the feed continues.
    private func dismissDrag(height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                guard isCompleted else { return }
                model.dragOffset = v.translation.height
            }
            .onEnded { v in
                guard isCompleted else { return }
                let dy = v.translation.height, flick = v.predictedEndTranslation.height
                let commit = abs(dy) > h * 0.2 || abs(flick) > h * 0.5
                let up = (abs(flick) > abs(dy) ? flick : dy) < 0
                withAnimation(.spring(duration: 0.35, bounce: 0)) {
                    if commit { model.dismissCard(up: up) } else { model.dragOffset = 0 }
                }
            }
    }

    private var debugBadge: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                showDebug.toggle()
            } label: {
                Text("\(model.counter.count)/\(model.scheduler.config.interval)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())
                    .foregroundStyle(.white)
            }
            if showDebug {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("packs: \(model.packSummary)")
                    ForEach(model.store.errors, id: \.self) { Text($0).foregroundStyle(.red) }
                    if let e = model.scheduler.configError { Text(e).foregroundStyle(.red) }
                    Text(model.currentURL).lineLimit(1).truncationMode(.middle)
                    Text(model.lastLog).lineLimit(2)
                    ForEach(model.events.suffix(6), id: \.self) { Text($0).lineLimit(1) }
                    Button("Inspect screen") {
                        model.webView?.evaluateJavaScript("window.__tq && window.__tq.inspect(); 0", completionHandler: nil)
                    }
                    Button("Copy log") { UIPasteboard.general.string = model.debugReport }
                    Button("Reload page") { model.webView?.reload() }
                    Button("Go to feed") { model.webView?.load(URLRequest(url: AppModel.feedURL)) }
                    Button("Arm now") { model.fireNow() }
                    Button("Reload packs") { model.reload() }
                }
                .font(.caption2)
                .padding(8)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
            }
        }
        .padding(.top, 50)
        .padding(.trailing, 12)
    }
}

/// Hosts tiktok.com. Config per plan.md: inline playback, autoplay, persistent cookies, bridge script.
struct TikTokWebView: UIViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .default()
        let desktop = model.scheduler.config.useDesktopSite
        if desktop {
            cfg.defaultWebpagePreferences.preferredContentMode = .desktop
        } else {
            // Default WKWebView UA lacks the "Version/x Safari/x" suffix; Google OAuth refuses
            // sign-in from anything that doesn't look like real Safari. Mobile mode only: in
            // desktop mode this suffix (it contains "Mobile") makes TikTok serve mobile web.
            cfg.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        }
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        cfg.userContentController.add(model.bridge, name: Bridge.handlerName)
        cfg.userContentController.addUserScript(model.makeUserScript())

        let web = ZoomingWebView(frame: .zero, configuration: cfg)
        if desktop {
            web.customUserAgent = AppModel.desktopUserAgent
            web.layoutWidth = CGFloat(model.scheduler.config.desktopLayoutWidth)
        }
        // SPA route changes (pushState) don't fire navigation callbacks; watch the URL itself.
        context.coordinator.urlObservation = web.observe(\.url, options: [.new]) { [model] w, _ in
            Task { @MainActor in model.currentURL = w.url?.absoluteString ?? "" }
        }
        model.note(desktop ? "site: desktop (Mac Safari UA)" : "site: mobile")
        web.uiDelegate = context.coordinator
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        // Frame already excludes status bar/home indicator; insets would shift the page down
        // while 100vh stays full height, cutting off the bottom.
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            web.isInspectable = true
        }
        // Desktop: first load waits for the zoom, else TikTok sizes the layout for the unzoomed width.
        web.loadWhenZoomed(URLRequest(url: URL(string: "https://www.tiktok.com")!))
        model.attach(web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: Bridge.handlerName)
    }

    /// Handles window.open (OAuth popups like "Continue with Google") by presenting a sheet,
    /// and page-health events (process crash, dead pages).
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let model: AppModel
        var urlObservation: NSKeyValueObservation?
        init(model: AppModel) { self.model = model }

        // MARK: Navigation policy

        /// Keep everything inside the wrapper: no app-scheme hand-offs (snssdk1233://, tiktok://,
        /// itms-apps://) and no universal links that would open the TikTok app.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
            let p = url.path.lowercased()
            if p.contains("redirect") || p.contains("download") {
                model.note("policy \(navigationAction.targetFrame?.isMainFrame == false ? "subframe" : "main") \(url.host ?? "?")\(url.path) → \(Coordinator.isAppHandoff(url) ? "cancel" : "allow")")
            }
            if Coordinator.isAppHandoff(url) {
                model.note("blocked app hand-off: \(url.absoluteString.prefix(80))")
                return decisionHandler(.cancel)
            }
            // .allow + 2 == WKNavigationActionPolicyAllowWithoutTryingAppLink: load in the web view
            // even when the URL is a universal link claimed by an installed app.
            decisionHandler(WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow)
        }

        static func isAppHandoff(_ url: URL) -> Bool {
            let scheme = (url.scheme ?? "").lowercased()
            if !["http", "https", "about", "blob", "data", "file"].contains(scheme) { return true }
            let host = (url.host ?? "").lowercased()
            if host == "apps.apple.com" || host == "itunes.apple.com" || host.hasSuffix(".onelink.me") { return true }
            if host.hasSuffix("tiktok.com") {
                let path = url.path.lowercased()
                // Mobile web's swipe cap navigates here before bouncing to the App Store.
                if path == "/redirect" || path.hasPrefix("/download-link") || path == "/download" { return true }
                // TikTok Studio/upload: rejects this browser and has no way back to the feed.
                if path.hasPrefix("/tiktokstudio") || path.hasPrefix("/creator") || path.hasPrefix("/upload") { return true }
            }
            if host.hasPrefix("studio.") || host.hasPrefix("creator.") { return true }
            return false
        }

        // MARK: Navigation / health

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.currentURL = webView.url?.absoluteString ?? ""
            model.note("→ \(webView.url?.path ?? "?")")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.currentURL = webView.url?.absoluteString ?? ""
            Task { @MainActor [model] in
                try? await Task.sleep(for: .seconds(4))
                model.checkPageHealth()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.note("nav failed: \((error as NSError).code) \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.note("load failed: \((error as NSError).code)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            model.contentProcessTerminated()
        }

        // MARK: Popups

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, Coordinator.isAppHandoff(url) {
                model.note("blocked app hand-off popup: \(url.absoluteString.prefix(80))")
                return nil
            }
            // Must use the supplied configuration so the popup shares the opener's session.
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.customUserAgent = webView.customUserAgent
            popup.uiDelegate = self
            if #available(iOS 16.4, *) { popup.isInspectable = true }
            model.popup = PopupWindow(webView: popup)
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            if model.popup?.webView === webView { model.popup = nil }
        }
    }
}

/// Lays the page out at `layoutWidth` CSS px and zooms it to fit the view, like a desktop
/// browser window shrunk onto the phone. 0 = no zoom.
final class ZoomingWebView: WKWebView {
    var layoutWidth: CGFloat = 0 { didSet { setNeedsLayout() } }
    private var pendingLoad: URLRequest?

    func loadWhenZoomed(_ request: URLRequest) {
        if layoutWidth > 0 && bounds.width == 0 { pendingLoad = request } else { load(request) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard layoutWidth > 0, bounds.width > 0 else { return }
        let zoom = min(1, bounds.width / layoutWidth)
        if abs(pageZoom - zoom) > 0.005 { pageZoom = zoom }
        if let r = pendingLoad { pendingLoad = nil; load(r) }
    }
}

/// A popup window opened by the page (OAuth). Identifiable so SwiftUI can present it.
struct PopupWindow: Identifiable {
    let id = UUID()
    let webView: WKWebView
}

struct PopupWebView: View {
    let popup: PopupWindow
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            PopupWebViewHost(webView: popup.webView)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Close") { onClose() } }
                }
        }
    }
}

struct PopupWebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
