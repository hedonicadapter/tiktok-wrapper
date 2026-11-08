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
    @Published var dismissUp = true             // direction the card leaves in
    @Published var popup: PopupWindow?          // window.open target (OAuth sign-in)
    @Published var lastLog: String = ""
    @Published var currentURL: String = ""
    @Published private(set) var events: [String] = []   // recent navigation/recovery events

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
            Task { @MainActor in
                self?.lastLog = msg
                if msg != "feed-observer installed" { self?.note("js: \(msg)") }
            }
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

    /// Card swiped away (either direction). Feed advances one video and resumes.
    func dismissCard(up: Bool = true) {
        guard case .completed = phase else { return }
        dismissUp = up
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

    /// Pages where TikTok's own UI is the whole experience; anywhere else gets a native back button.
    var isOnFeed: Bool {
        guard let path = URL(string: currentURL)?.path.lowercased() else { return true }
        return ["", "/", "/foryou", "/following", "/friends", "/explore", "/live"].contains(path)
    }

    func goBackOrFeed() {
        guard let web = webView else { return }
        if web.canGoBack { web.goBack() } else { web.load(URLRequest(url: AppModel.feedURL)) }
    }

    /// Debug/manual trigger: arm immediately.
    func fireNow() {
        guard phase == .hidden, let next = scheduler.nextInterrupt() else { return }
        arm(next)
    }

    // MARK: Page health

    static let feedURL = URL(string: "https://www.tiktok.com/foryou")!
    /// Exactly what Safari on macOS sends. No "Mobile" token anywhere, or TikTok serves mobile web.
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private var recoveries: [Date] = []

    func note(_ s: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        events.append("\(stamp) \(s)")
        if events.count > 60 { events.removeFirst(events.count - 60) }
        #if DEBUG
        print("[tq] \(s)")
        #endif
    }

    /// "korkort-emil 12/726 retired, …" — mastery progress per pack.
    var packSummary: String {
        store.packs.map { p in
            let r = p.retiredCount(progress: scheduler.loadProgress(packId: p.id))
            return r > 0 ? "\(p.id) \(r)/\(p.itemCount) retired" : "\(p.id) (\(p.itemCount))"
        }.joined(separator: ", ")
    }

    /// Everything the debug panel knows, for pasting into a bug report.
    var debugReport: String {
        var lines = ["ScrollGate \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")",
                     "url: \(currentURL)",
                     "count: \(counter.count)/\(scheduler.config.interval)  desktopSite: \(scheduler.config.useDesktopSite)",
                     "packs: \(packSummary)"]
        lines += store.errors.map { "pack error: \($0)" }
        if let e = scheduler.configError { lines.append("config error: \(e)") }
        lines += events
        return lines.joined(separator: "\n")
    }

    /// Web content process died (memory pressure). WKWebView shows blank until reloaded.
    func contentProcessTerminated() {
        note("web process terminated → reload")
        recover(reason: "process-terminated")
    }

    /// A few seconds after a page load, check it isn't a dead page (no text, no video, no controls).
    func checkPageHealth() {
        guard let web = webView else { return }
        let js = """
        (function(){
          var b = document.body; if (!b) return 'nobody';
          var text = (b.innerText || '').trim().length;
          var things = document.querySelectorAll('video,input,button,a,[role=button]').length;
          return (text < 20 && things === 0) ? 'dead' : 'ok:' + text + ':' + things;
        })()
        """
        web.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            let r = result as? String ?? "unknown"
            if r == "dead" || r == "nobody" {
                self.note("dead page at \(self.currentURL) → recover")
                self.recover(reason: "dead-page")
            }
        }
    }

    /// Reload once; second recovery within a minute goes to the feed URL; then give up until later.
    private func recover(reason: String) {
        guard let web = webView else { return }
        let now = Date()
        recoveries = recoveries.filter { now.timeIntervalSince($0) < 60 }
        recoveries.append(now)
        switch recoveries.count {
        case 1:
            web.reload()
        case 2:
            note("second recovery → load feed URL")
            web.load(URLRequest(url: AppModel.feedURL))
        default:
            note("recovery limit hit (\(reason)); leaving page as is")
        }
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
