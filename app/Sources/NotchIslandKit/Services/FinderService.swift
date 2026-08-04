// File: Sources/NotchIsland/Services/FinderService.swift
import AppKit
import Combine

/// Manages the Finder Shelf: pinning URLs, persisting them as security-scoped
/// bookmarks, resolving (and refreshing) them, and opening/revealing targets.
final class FinderService: FinderServiceProtocol {
    let items = CurrentValueSubject<[FinderShelfItem], Never>([])
    private let store: CodableStore<[FinderShelfItem]>

    init(store: CodableStore<[FinderShelfItem]> = CodableStore(filename: "finder_shelf.json")) {
        self.store = store
        items.send(store.load(default: []))
    }

    private func persist() { store.save(items.value) }

    func addItem(url: URL) {
        let kind: FinderShelfItemKind
        if url.pathExtension == "app" {
            kind = .application
        } else {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            kind = isDir.boolValue ? .folder : .file
        }

        let bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
        let item = FinderShelfItem(
            displayName: url.lastPathComponent,
            bookmarkData: bookmark,
            fallbackPath: url.path,
            kind: kind
        )
        var current = items.value
        // Avoid duplicate paths.
        guard !current.contains(where: { $0.fallbackPath == url.path }) else { return }
        current.append(item)
        items.send(current)
        persist()
        Log.finder.info("Pinned item kind=\(kind.rawValue, privacy: .public)")
    }

    func removeItem(id: UUID) {
        items.send(items.value.filter { $0.id != id })
        persist()
    }

    func resolveURL(for item: FinderShelfItem) -> URL? {
        if let data = item.bookmarkData {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                if stale { refreshBookmark(for: item, resolvedURL: url) }
                return url
            }
        }
        // Fallback to plain path if it still exists.
        if let path = item.fallbackPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func refreshBookmark(for item: FinderShelfItem, resolvedURL: URL) {
        let didAccess = resolvedURL.startAccessingSecurityScopedResource()
        defer { if didAccess { resolvedURL.stopAccessingSecurityScopedResource() } }
        guard let fresh = try? resolvedURL.bookmarkData(options: [.withSecurityScope],
                                                        includingResourceValuesForKeys: nil,
                                                        relativeTo: nil) else { return }
        var current = items.value
        if let idx = current.firstIndex(where: { $0.id == item.id }) {
            current[idx].bookmarkData = fresh
            items.send(current)
            persist()
        }
    }

    func open(item: FinderShelfItem) {
        guard let url = resolveURL(for: item) else {
            Log.finder.error("Open failed: target missing")
            return
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(item: FinderShelfItem) {
        guard let url = resolveURL(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(item: FinderShelfItem) {
        guard let url = resolveURL(for: item) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
}
