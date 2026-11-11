import Foundation

struct LUTItem: Identifiable, Hashable {
    let name: String
    let url: URL
    var id: String { name }
}

/// Watches Documents/LUTs for .cube files. The folder is visible in the Files app.
final class LUTLibrary: ObservableObject {
    static let shared = LUTLibrary()

    @Published private(set) var items: [LUTItem] = []
    let folder: URL

    private let lock = NSLock()
    private var urlByName: [String: URL] = [:]
    private var cache: [String: LUTCube] = [:]   // key: path|modDate

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("LUTs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        seedBundledLUTs()
        scan()
    }

    /// First launch only: copy the sample LUTs shipped in the app into the user-visible LUTs folder.
    private func seedBundledLUTs() {
        let key = "balutcam.seededLUTs"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let bundled = Bundle.main.urls(forResourcesWithExtension: "cube", subdirectory: "LUTs") ?? []
        for url in bundled {
            let dest = folder.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: url, to: dest)
            }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    func scan() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        let found = urls
            .filter { $0.pathExtension.lowercased() == "cube" }
            .map { LUTItem(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        lock.lock()
        urlByName = Dictionary(found.map { ($0.name, $0.url) }, uniquingKeysWith: { a, _ in a })
        lock.unlock()

        if Thread.isMainThread { items = found } else { DispatchQueue.main.async { self.items = found } }
    }

    /// Returns the parsed LUT (cached). Safe to call from any thread.
    func cube(named name: String?) -> LUTCube? {
        guard let name else { return nil }
        lock.lock()
        let url = urlByName[name]
        lock.unlock()
        guard let url else { return nil }

        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(mod)"

        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard let cube = try? CubeParser.parse(url: url) else { return nil }
        lock.lock()
        cache[key] = cube
        lock.unlock()
        return cube
    }

    /// Copies a user-picked file into the LUTs folder after checking that it parses.
    func importFile(at source: URL) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        _ = try CubeParser.parse(url: source)   // validate before copying
        let dest = folder.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: source, to: dest)
        scan()
    }

    func delete(_ item: LUTItem) {
        try? FileManager.default.removeItem(at: item.url)
        scan()
    }
}
