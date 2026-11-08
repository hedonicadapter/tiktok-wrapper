import Foundation

/// Documents/config.json
struct SchedulerConfig: Codable, Equatable {
    var interval: Int = 5
    var hardMode: Bool = false
    var packs: [String: Double] = [:]      // pack id -> weight; 0 parks it
    var quietHours: [String]? = nil        // ["23:00", "07:00"]
    var debug: Bool? = nil                 // show counter badge + debug panel (default true)
    var desktopSite: Bool? = nil           // tiktok.com desktop layout (default true: mobile web caps swipes and redirects to the app)

    var useDesktopSite: Bool { desktopSite ?? true }
    var desktopWidth: Double? = nil        // CSS px the desktop layout gets; page is zoomed to fit the screen

    /// Desktop TikTok overflows below ~500 CSS px (right action bar off-screen); 560 fits with margin.
    var desktopLayoutWidth: Double { max(480, desktopWidth ?? 560) }

    var showDebug: Bool { debug ?? true }

    static let `default` = SchedulerConfig(
        interval: 5, hardMode: false,
        packs: ["drivers-ed": 3, "stretch": 1, "blank-prompt": 1],
        quietHours: ["23:00", "07:00"])
}

/// Picks which pack fires next (weighted), asks it for an item, persists per-pack progress.
final class Scheduler: ObservableObject {
    @Published private(set) var config: SchedulerConfig = .default
    @Published private(set) var configError: String?

    private let store: PackStore
    private let defaults: UserDefaults
    private var random: (Double) -> Double = { Double.random(in: 0..<$0) }

    init(store: PackStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    // MARK: Config

    func reloadConfig() {
        guard let data = try? Data(contentsOf: store.configURL) else {
            config = .default
            configError = nil
            return
        }
        do {
            config = try JSONDecoder().decode(SchedulerConfig.self, from: data)
            configError = nil
        } catch {
            configError = "config.json: \(error)"
            // Keep previous config; never crash feed.
        }
    }

    // MARK: Quiet hours

    func isQuiet(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let q = config.quietHours, q.count == 2,
              let start = minutes(q[0]), let end = minutes(q[1]) else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if start == end { return false }
        return start < end ? (now >= start && now < end) : (now >= start || now < end)
    }

    private func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    // MARK: Picking

    /// Weighted pick among loaded packs with weight > 0. Packs missing from config get weight 0
    /// unless config has no packs section at all, then every loaded pack gets weight 1.
    func pickPack() -> LoadedPack? {
        let available = store.packs
        guard !available.isEmpty else { return nil }
        let weighted: [(LoadedPack, Double)] = available.compactMap { p in
            let w = config.packs.isEmpty ? 1.0 : (config.packs[p.id] ?? 0)
            return w > 0 ? (p, w) : nil
        }
        guard !weighted.isEmpty else { return nil }
        let total = weighted.reduce(0) { $0 + $1.1 }
        var r = random(total)
        for (p, w) in weighted {
            r -= w
            if r < 0 { return p }
        }
        return weighted.last?.0
    }

    func nextInterrupt() -> ScheduledInterrupt? {
        guard let pack = pickPack() else { return nil }
        let progress = loadProgress(packId: pack.id)
        guard let picked = pack.next(progress: progress) else { return nil }
        var unlock = pack.unlock
        if config.hardMode, pack.kind == .quiz || pack.kind == .flashcard { unlock = .correct }
        return ScheduledInterrupt(packId: pack.id, packTitle: pack.title, itemId: picked.itemId,
                                  interrupt: picked.interrupt, unlock: unlock, hardMode: config.hardMode,
                                  hideSelectors: pack.hideSelectors)
    }

    func record(_ scheduled: ScheduledInterrupt, result: InterruptResult) {
        guard let pack = store.pack(id: scheduled.packId) else { return }
        var progress = loadProgress(packId: pack.id)
        pack.record(itemId: scheduled.itemId, result: result, progress: &progress)
        saveProgress(progress, packId: pack.id)
    }

    // MARK: Progress persistence

    private func progressKey(_ packId: String) -> String { "tq.progress.\(packId)" }

    func loadProgress(packId: String) -> PackProgress {
        guard let data = defaults.data(forKey: progressKey(packId)),
              let p = try? JSONDecoder().decode(PackProgress.self, from: data) else { return PackProgress() }
        return p
    }

    func saveProgress(_ p: PackProgress, packId: String) {
        if let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: progressKey(packId))
        }
    }
}
