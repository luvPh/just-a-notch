// File: Sources/NotchIsland/Core/Models/FinderShelfItem.swift
import Foundation

enum FinderShelfItemKind: String, Codable, Equatable {
    case folder
    case file
    case application
}

/// A pinned Finder location. Persisted via a security-scoped bookmark with a
/// plain-path fallback for display when the bookmark is stale/unresolvable.
struct FinderShelfItem: Identifiable, Codable, Equatable {
    var id: UUID
    var displayName: String
    var bookmarkData: Data?
    var fallbackPath: String?
    var kind: FinderShelfItemKind
    var dateAdded: Date

    init(id: UUID = UUID(),
         displayName: String,
         bookmarkData: Data? = nil,
         fallbackPath: String? = nil,
         kind: FinderShelfItemKind,
         dateAdded: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.bookmarkData = bookmarkData
        self.fallbackPath = fallbackPath
        self.kind = kind
        self.dateAdded = dateAdded
    }
}
