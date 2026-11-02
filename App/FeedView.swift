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
                TikTokWebView(model: model)
                    .ignoresSafeArea()

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

                #if DEBUG
                debugBadge.zIndex(2)
                #endif
            }
        }
        .ignoresSafeArea()   // geo = full screen, so the card covers the whole feed
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
        case .completed: return min(0, model.dragOffset)          // dragging up and away
        case .dismissing: return -h
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

    /// After unlock, swipe up dismisses the card and the feed continues.
    private func dismissDrag(height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                guard isCompleted else { return }
                model.dragOffset = min(0, v.translation.height)
            }
            .onEnded { v in
                guard isCompleted else { return }
                let commit = -v.translation.height > h * 0.2 || -v.predictedEndTranslation.height > h * 0.5
                withAnimation(.spring(duration: 0.35, bounce: 0)) {
                    if commit { model.dismissCard() } else { model.dragOffset = 0 }
                }
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
    #endif
}

/// Hosts tiktok.com. Config per plan.md: inline playback, autoplay, persistent cookies, bridge script.
struct TikTokWebView: UIViewRepresentable {
    let model: AppModel

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .default()
        cfg.userContentController.add(model.bridge, name: Bridge.handlerName)
        cfg.userContentController.addUserScript(model.makeUserScript())

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) {
            web.isInspectable = true
        }
        web.load(URLRequest(url: URL(string: "https://www.tiktok.com")!))
        model.attach(web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: Bridge.handlerName)
    }
}
