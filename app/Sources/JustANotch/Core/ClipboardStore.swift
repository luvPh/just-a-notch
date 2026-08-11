// app/Sources/JustANotch/Core/ClipboardStore.swift
import Foundation
import Combine
import AppKit

/// Theo dõi NSPasteboard, giữ lịch sử copy (text + ảnh), lưu bền ra JSON.
/// Lõi mutation nằm ở ClipboardHistory; store lo I/O + side-effects.
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private var history: ClipboardHistory
    private let fileURL: URL
    private let imagesDir: URL?

    // Chống loop: changeCount của lần chính store ghi ra pasteboard.
    private var selfChangeCount: Int = -1
    private var lastSeenChangeCount: Int = NSPasteboard.general.changeCount
    private var pollTimer: Timer?

    static let unpinnedLimit = 25

    static var defaultFileURL: URL {
        Self.appSupport().appendingPathComponent("clipboard.json")
    }
    static var defaultImagesDir: URL {
        let d = Self.appSupport().appendingPathComponent("Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func appSupport() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    init(fileURL: URL = ClipboardStore.defaultFileURL,
         imagesDir: URL? = ClipboardStore.defaultImagesDir,
         autoPoll: Bool = true) {
        self.fileURL = fileURL
        self.imagesDir = imagesDir
        self.history = ClipboardHistory(unpinnedLimit: Self.unpinnedLimit)
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            self.history = ClipboardHistory(unpinnedLimit: Self.unpinnedLimit, items: saved)
        }
        self.items = history.items
        if autoPoll { startPolling() }
    }

    // MARK: Public mutations (UI + tests)
    func recordText(_ s: String) {
        let item = ClipboardItem(id: UUID(), createdAt: Date(), pinned: false, kind: .text(s))
        applyRecorded(history.record(item))
    }

    func togglePin(_ id: UUID) { history.togglePin(id); sync() }

    func delete(_ id: UUID) {
        if let removed = history.remove(id) { cleanupFile(for: removed) }
        sync()
    }

    func clearUnpinned() {
        history.clearUnpinned().forEach(cleanupFile(for:))
        sync()
    }

    /// Copy một mục trở lại pasteboard (không auto-paste).
    func copyBack(_ id: UUID) {
        guard let item = history.items.first(where: { $0.id == id }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case let .text(s):
            pb.setString(s, forType: .string)
        case let .image(fileName):
            if let dir = imagesDir,
               let img = NSImage(contentsOf: dir.appendingPathComponent(fileName)) {
                pb.writeObjects([img])
            }
        }
        selfChangeCount = pb.changeCount        // đừng tự ghi lại mục này
    }

    // MARK: Internals
    private func applyRecorded(_ removed: [ClipboardItem]) {
        removed.forEach(cleanupFile(for:))
        sync()
    }

    private func sync() {
        items = history.items
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(history.items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func cleanupFile(for item: ClipboardItem) {
        guard case let .image(fileName) = item.kind, let dir = imagesDir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName))
    }

    // startPolling() / pasteboard reading added in Task 3.
    private func startPolling() {}
}
