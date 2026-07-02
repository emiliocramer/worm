import Foundation

/// A tiny file-backed cache for a single Codable value, stored as JSON in the
/// app's Application Support directory. Used so each node can persist its full
/// synced snapshot and show it instantly on the next launch instead of
/// re-fetching everything from scratch.
struct SnapshotStore<Value: Codable> {
    let filename: String

    private var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL {
        directoryURL.appendingPathComponent(filename)
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Caching is best-effort; a failure here just means a slower next
            // launch, never a correctness problem.
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
