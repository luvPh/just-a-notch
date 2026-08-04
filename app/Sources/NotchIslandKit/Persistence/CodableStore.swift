// File: Sources/NotchIsland/Persistence/CodableStore.swift
import Foundation

/// Small atomic JSON store for Codable collections. Never crashes on missing or
/// corrupt data — it logs and returns the provided default.
final class CodableStore<T: Codable> {
    private let url: URL
    private let queue = DispatchQueue(label: "com.notchisland.codablestore")

    init(filename: String) {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("NotchIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)
    }

    func load(default defaultValue: T) -> T {
        queue.sync {
            guard let data = try? Data(contentsOf: url) else { return defaultValue }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                Log.persistence.error("Decode failed for \(self.url.lastPathComponent, privacy: .public); using default")
                return defaultValue
            }
        }
    }

    func save(_ value: T) {
        queue.sync {
            do {
                let data = try JSONEncoder().encode(value)
                try data.write(to: url, options: .atomic)
            } catch {
                Log.persistence.error("Save failed for \(self.url.lastPathComponent, privacy: .public)")
            }
        }
    }
}
