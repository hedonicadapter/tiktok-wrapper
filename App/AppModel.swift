import Foundation
import Combine
import WebKit

/// Glue: counter + scheduler + pending-interrupt persistence. Owns the web view's control calls.
@MainActor
final class AppModel: ObservableObject {
    @Published var active: ScheduledInterrupt?
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

        // Relaunch with unresolved interrupt → show it again.
        if let data = defaults.data(forKey: pendingKey),
           let pending = try? JSONDecoder().decode(ScheduledInterrupt.self, from: data) {
            active = pending
        }
    }

    /// Re-read packs + config (call on launch and on foreground so Files-app edits take effect).
    func reload() {
        store.reload()
        scheduler.reloadConfig()
    }

    func makeUserScript() -> WKUserScript {
        Bridge.makeUserScript(hideSelectors: store.loadHideSelectors())
    }

    // MARK: Flow

    private func handleVideo(_ id: String) {
        #if DEBUG
        print("[tq] video \(id)")
        #endif
        guard counter.register(id) else { return }
        guard active == nil else { return }
        guard counter.shouldFire(interval: scheduler.config.interval) else { return }

        if scheduler.isQuiet() {
            counter.reset()
            return
        }
        guard let next = scheduler.nextInterrupt() else {
            // No usable packs — don't block the feed, just reset.
            counter.reset()
            return
        }
        present(next)
    }

    func present(_ s: ScheduledInterrupt) {
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: pendingKey) }
        pauseFeed()
        active = s
    }

    func complete(_ s: ScheduledInterrupt, result: InterruptResult) {
        scheduler.record(s, result: result)
        defaults.removeObject(forKey: pendingKey)
        counter.reset()
        active = nil
        resumeFeed()
    }

    /// Debug/manual trigger.
    func fireNow() {
        guard active == nil, let next = scheduler.nextInterrupt() else { return }
        present(next)
    }

    // MARK: Feed control

    func pauseFeed() {
        webView?.evaluateJavaScript("window.__tq && window.__tq.pause(); 0", completionHandler: nil)
    }

    func resumeFeed() {
        webView?.evaluateJavaScript("window.__tq && window.__tq.resume(); 0", completionHandler: nil)
    }
}
