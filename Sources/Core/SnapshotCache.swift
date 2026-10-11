import Foundation

/// Last good snapshot per provider, so the menu has numbers right after launch. Holds no secrets.
public actor SnapshotCache {
    private let url: URL

    public init(url: URL = AppPaths.supportDirectory.appending(path: "snapshots-v1.json")) {
        self.url = url
    }

    public func load() -> [ProviderID: ProviderSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        do {
            return try JSONDecoder().decode([ProviderID: ProviderSnapshot].self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return [:]
        }
    }

    public func save(_ snapshots: [ProviderID: ProviderSnapshot]) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshots)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.store.error("Could not save snapshot cache")
        }
    }
}
