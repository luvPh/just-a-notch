// File: Sources/NotchIsland/Core/Models/IslandState.swift
import Foundation

/// The kind of content currently surfaced by the island.
enum IslandContent: Equatable {
    case media
    case notification
    case systemStatus
    case finderShelf
}

/// Selects the first useful island screen without turning the island into a
/// launcher. Kept pure so the launch/toggle policy is regression-testable.
enum IslandDefaultContent {
    static func select(mediaAvailable: Bool) -> IslandContent {
        mediaAvailable ? .media : .systemStatus
    }
}

/// Presentation state of the Dynamic Island. This is the single source of
/// truth for what the UI shows; UI must never derive layout from loose booleans.
enum IslandPresentationState: Equatable {
    case hidden
    case compact
    case hoverPreview
    case expanded(IslandContent)
    case pinned(IslandContent)
    case editing

    var isExpandedLike: Bool {
        switch self {
        case .expanded, .pinned, .editing: return true
        case .hidden, .compact, .hoverPreview: return false
        }
    }

    /// Content associated with the state, if any.
    var content: IslandContent? {
        switch self {
        case .expanded(let c), .pinned(let c): return c
        default: return nil
        }
    }
}

// MARK: - Events

enum IslandEventPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    static func < (lhs: IslandEventPriority, rhs: IslandEventPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum IslandEventType: Equatable {
    case mediaChanged
    case notification
    case systemAlert
    case finderPinned
    case custom(String)
}

/// Lightweight payload for an event. Kept small and non-sensitive.
struct IslandEventPayload: Equatable {
    var title: String
    var subtitle: String?
    var symbolName: String?
    var content: IslandContent?

    init(title: String, subtitle: String? = nil, symbolName: String? = nil, content: IslandContent? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.content = content
    }
}

struct IslandEvent: Identifiable, Equatable {
    let id: UUID
    let type: IslandEventType
    let priority: IslandEventPriority
    let createdAt: Date
    let duration: TimeInterval?
    let payload: IslandEventPayload

    init(id: UUID = UUID(),
         type: IslandEventType,
         priority: IslandEventPriority = .normal,
         createdAt: Date = Date(),
         duration: TimeInterval? = 3.0,
         payload: IslandEventPayload) {
        self.id = id
        self.type = type
        self.priority = priority
        self.createdAt = createdAt
        self.duration = duration
        self.payload = payload
    }
}
