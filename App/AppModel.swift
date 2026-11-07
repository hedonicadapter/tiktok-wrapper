import Foundation
import Combine
import WebKit
import UIKit

/// Lifecycle of the feed card (the interrupt presented as if it were the next video).
enum CardPhase: Equatable {
    case hidden
    case armed                      // count hit N; next swipe drags the card in
    case shown                      // card on screen, unlock rule not yet met
    case completed(InterruptResult) // unlocked; swipe up dismisses
    case dismissing
}

/// Glue: counter + scheduler + card state + pending-interrupt persistence.
@MainActor
final class AppModel: ObservableObject {
    @Published var card: ScheduledInterrupt?
    @Published var phase: CardPhase = .hidden
    @Published var dragOffset: CGFloat = 0      // live finger translation while dragging card
    @Published var popup: PopupWindow?          // window.open target (OAuth sign-in)
    @Published var lastLog: String = ""

    let store: PackStore
    let scheduler: Scheduler
    let counter: SwipeCounter
    let bridge = Bridge()

    weak var webView: WKWebView?
    private let defaults: UserDefaults
    private let pendingKey = "tq.pending"
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = PackStore()
        scheduler = Scheduler(store: store, defaults: defaults)
        counter = SwipeCounter(defaults: defaults)

        store.installStartersIfNeeded()
        reload()

        // Forward nested changes so views observing AppModel refresh.
        for child in [store.objectWillChange.eraseToAnyPublisher(),
                      scheduler.objectWillChange.eraseToAnyPublisher(),
                      counter.objectWillChange.eraseToAnyPublisher()] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }

        bridge.onVideo = { [weak self] id in
            Task { @MainActor in self?.handleVideo(id) }
        }
        bridge.onLog = { [weak self] msg in
            Task { @MainActor in self?.lastLog = msg }
            #if DEBUG
            print("[tq] \(msg)")
            #endif
        }

        // Relaunch with unresolved interrupt → show card directly, no gesture.
        if let data = defaults.data(forKey: pendingKey),
           let pending = try? JSONDecoder().decode(ScheduledInterrupt.self, from: data) {
            card = pending
            phase = .shown
        }
    }

    /// Re-read packs + config (call on launch and on foreground so Files-app edits take effect).
    func reload() {
        store.reload()
        scheduler.reloadConfig()
    }

    func makeUserScript() -> WKUserScript {
        Bridge.makeUserScript(selectors: store.loadHideSelectors())
    }

    /// Called by the web view once created; applies current lock state.
    func attach(_ web: WKWebView) {
        webView = web
        applyScrollLock()
    }

    // MARK: Flow

    private func handleVideo(_ id: String) {
        #if DEBUG
        print("[tq] video \(id)")
        #endif
        guard counter.register(id) else { return }
        guard phase == .hidden else { return }
        guard counter.shouldFire(interval: scheduler.config.interval) else { return }

        if scheduler.isQuiet() {
            counter.reset()
            return
        }
        guard let next = scheduler.nextInterrupt() else {
            counter.reset()     // no usable packs: never block the feed
            return
        }
        arm(next)
    }

    /// Count reached N. Card waits just below the screen; the next swipe drags it in.
    func arm(_ s: ScheduledInterrupt) {
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: pendingKey) }
        card = s
        dragOffset = 0
        phase = .armed
        applyScrollLock()
    }

    /// Swipe committed: card snaps fully on screen, feed pauses.
    func showCard() {
        guard phase == .armed else { return }
        pauseFeed()
        dragOffset = 0
        phase = .shown
    }

    /// Unlock rule met inside the card. Card stays until the user swipes it away.
    func cardCompleted(_ result: InterruptResult) {
        guard case .shown = phase, let card else { return }
        scheduler.record(card, result: result)
        defaults.removeObject(forKey: pendingKey)
        phase = .completed(result)
    }

    /// Card swiped off the top. Feed advances one video and resumes.
    func dismissCard() {
        guard case .completed = phase else { return }
        phase = .dismissing
        counter.reset()
        applyScrollLock(unlock: true)
        advanceFeed()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            card = nil
            dragOffset = 0
            phase = .hidden
            resumeFeed()
        }
    }

    /// Debug/manual trigger: arm immediately.
    func fireNow() {
        guard phase == .hidden, let next = scheduler.nextInterrupt() else { return }
        arm(next)
    }

    // MARK: Feed control

    private func applyScrollLock(unlock: Bool = false) {
        let locked = !unlock && phase != .hidden
        webView?.scrollView.isScrollEnabled = !locked
    }

    func pauseFeed() {
        webView?.evaluateJavaScript("window.__tq && window.__tq.pause(); 0", completionHandler: nil)
    }

    func resumeFeed() {
        webView?.evaluateJavaScript("window.__tq && window.__tq.resume(); 0", completionHandler: nil)
    }

    /// Best effort: scroll feed one page so the card feels inserted between two videos.
    func advanceFeed() {
        webView?.evaluateJavaScript("window.__tq && window.__tq.next(); 0", completionHandler: nil)
    }
}
