import Foundation

/// Discovers packs in Documents/packs/*/manifest.json. Copies bundled starter packs
/// and default config on first launch. Never throws into the feed: broken packs land in `errors`.
final class PackStore: ObservableObject {
    @Published private(set) var packs: [LoadedPack] = []
    @Published private(set) var errors: [String] = []

    let documents: URL
    var packsDir: URL { documents.appendingPathComponent("packs", isDirectory: true) }
    var configURL: URL { documents.appendingPathComponent("config.json") }
    var hideSelectorsURL: URL { documents.appendingPathComponent("hide-selectors.json") }

    private let fm = FileManager.default

    init(documents: URL? = nil) {
        self.documents = documents
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: First launch

    /// Copies starter packs, config.json and hide-selectors.json into Documents if absent.
    func installStartersIfNeeded() {
        try? fm.createDirectory(at: packsDir, withIntermediateDirectories: true)

        if let starters = Bundle.main.url(forResource: "starter-packs", withExtension: nil),
           let names = try? fm.contentsOfDirectory(atPath: starters.path) {
            for name in names {
                let src = starters.appendingPathComponent(name)
                let dst = packsDir.appendingPathComponent(name)
                if !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: src, to: dst)
                }
            }
        }
        if !fm.fileExists(atPath: configURL.path),
           let src = Bundle.main.url(forResource: "config.default", withExtension: "json") {
            try? fm.copyItem(at: src, to: configURL)
        }
        if let src = Bundle.main.url(forResource: "hide-selectors", withExtension: "json") {
            if !fm.fileExists(atPath: hideSelectorsURL.path) {
                try? fm.copyItem(at: src, to: hideSelectorsURL)
            } else if selectorsVersion(at: hideSelectorsURL) < selectorsVersion(at: src) {
                // Newer bundled list: replace, keeping the old one next to it.
                let backup = documents.appendingPathComponent("hide-selectors.old.json")
                try? fm.removeItem(at: backup)
                try? fm.moveItem(at: hideSelectorsURL, to: backup)
                try? fm.copyItem(at: src, to: hideSelectorsURL)
            }
        }
    }

    // MARK: Hide / click selectors

    /// Legacy plain-array files and files without a version count as 0.
    func selectorsVersion(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONDecoder().decode(NagSelectors.self, from: data) else { return 0 }
        return obj.version ?? 0
    }

    /// Documents copy wins (editable in Files app); bundle copy is fallback.
    /// Accepts `{"hide": [...], "click": [...]}` or a legacy plain array (hide only).
    func loadHideSelectors() -> NagSelectors {
        for url in [hideSelectorsURL, Bundle.main.url(forResource: "hide-selectors", withExtension: "json")].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let obj = try? JSONDecoder().decode(NagSelectors.self, from: data) { return obj }
            if let list = try? JSONDecoder().decode([String].self, from: data) { return NagSelectors(hide: list, click: []) }
        }
        return NagSelectors(hide: [], click: [])
    }

    // MARK: Packs

    func reload() {
        var loaded: [LoadedPack] = []
        var errs: [String] = []

        let dirs = (try? fm.contentsOfDirectory(at: packsDir, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        for dir in dirs {
            switch load(packDir: dir, warnings: &errs) {
            case .success(let p): loaded.append(p)
            case .failure(let e): errs.append(e.description)
            }
        }
        packs = loaded
        errors = errs
    }

    func pack(id: String) -> LoadedPack? { packs.first { $0.id == id } }

    private func load(packDir: URL, warnings: inout [String]) -> Result<LoadedPack, PackError> {
        let name = packDir.lastPathComponent
        let manifestURL = packDir.appendingPathComponent("manifest.json")
        guard let mdata = try? Data(contentsOf: manifestURL) else { return .failure(.missingManifest(name)) }

        let manifest: PackManifest
        do { manifest = try JSONDecoder().decode(PackManifest.self, from: mdata) }
        catch { return .failure(.badManifest(name, String(describing: error))) }

        let itemsURL = packDir.appendingPathComponent(manifest.itemsFile)
        guard let idata = try? Data(contentsOf: itemsURL) else { return .failure(.missingItems(name, manifest.itemsFile)) }

        let raw: [PackItem]
        do {
            // Accept array, or single object for pack-of-one (web/read).
            if let arr = try? JSONDecoder().decode([PackItem].self, from: idata) { raw = arr }
            else { raw = [try JSONDecoder().decode(PackItem.self, from: idata)] }
        } catch { return .failure(.badItems(name, String(describing: error))) }

        var items: [(id: String, interrupt: Interrupt)] = []
        var seenIds = Set<String>()
        for (i, item) in raw.enumerated() {
            do {
                let interrupt = try item.toInterrupt(kind: manifest.kind, packDir: packDir)
                var id = item.id ?? "i\(i)"
                if seenIds.contains(id) { id = "\(id)#\(i)" }
                seenIds.insert(id)
                items.append((id, interrupt))
            } catch {
                warnings.append("\(name) item \(i): \(error)")
            }
        }
        guard !items.isEmpty else { return .failure(.empty(name)) }
        return .success(LoadedPack(manifest: manifest, items: items, directory: packDir))
    }
}
