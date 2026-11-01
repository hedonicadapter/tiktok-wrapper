import SwiftUI
import WebKit

struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDebug = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TikTokWebView(model: model)
                .ignoresSafeArea()

            #if DEBUG
            debugBadge
            #endif
        }
        .fullScreenCover(item: $model.active) { scheduled in
            InterruptOverlay(scheduled: scheduled) { result in
                model.complete(scheduled, result: result)
            }
            .interactiveDismissDisabled(true)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.reload()
                if model.active != nil { model.pauseFeed() }
            case .background, .inactive:
                if model.active != nil { model.pauseFeed() }
            @unknown default:
                break
            }
        }
        .onAppear {
            if model.active != nil { model.pauseFeed() }
        }
    }

    #if DEBUG
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
                    Text("packs: \(model.store.packs.map(\.id).joined(separator: ", "))")
                    ForEach(model.store.errors, id: \.self) { Text($0).foregroundStyle(.red) }
                    if let e = model.scheduler.configError { Text(e).foregroundStyle(.red) }
                    Text(model.lastLog).lineLimit(2)
                    Button("Fire now") { model.fireNow() }
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
    #endif
}

/// Hosts tiktok.com. Config per plan.md: inline playback, autoplay, persistent cookies, bridge script.
struct TikTokWebView: UIViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .default()
        cfg.userContentController.add(model.bridge, name: Bridge.handlerName)
        cfg.userContentController.addUserScript(model.makeUserScript())

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            web.isInspectable = true
        }
        web.load(URLRequest(url: URL(string: "https://www.tiktok.com")!))
        model.webView = web
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: Bridge.handlerName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        // Keep tiktok.com in-app; anything else (login providers etc.) also stays in-app
        // since OAuth popups need the same cookie store.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
