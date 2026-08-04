// File: Sources/NotchIsland/Island/IslandStateMachine.swift
import Foundation

/// Inputs that can drive island state transitions. Kept as pure values so the
/// machine is fully unit-testable without any AppKit/UI dependency.
enum IslandInput: Equatable {
    case hoverBegan
    case hoverEnded
    case clicked(IslandContent)
    case dismiss            // Escape or click-outside
    case pin
    case unpin
    case beginEditing
    case endEditing
    case event(IslandEvent)
    case eventExpired(UUID)
    case autoCollapse
}

/// Deterministic state machine for the Dynamic Island.
///
/// Rules implemented:
/// - Default is `.compact`.
/// - Hover -> `.hoverPreview` (the hover *delay* is handled by the caller/timer).
/// - Click -> `.expanded(content)`.
/// - Dismiss / auto-collapse -> back to `.compact` (unless pinned).
/// - `pin` freezes the current content as `.pinned`.
/// - High/critical events transiently take over; on expiry we return to the
///   state that was interrupted.
struct IslandStateMachine {
    private(set) var state: IslandPresentationState
    /// State to restore to after a transient event expires.
    private var interruptedState: IslandPresentationState?
    /// Id of the transient event currently displayed, if any.
    private(set) var activeTransientEventID: UUID?

    init(state: IslandPresentationState = .compact) {
        self.state = state
    }

    /// Apply an input and return the resulting state.
    @discardableResult
    mutating func handle(_ input: IslandInput) -> IslandPresentationState {
        switch input {
        case .hoverBegan:
            if case .compact = state { state = .hoverPreview }

        case .hoverEnded:
            if case .hoverPreview = state { state = .compact }

        case .clicked(let content):
            switch state {
            case .editing:
                break // ignore clicks while editing
            case .pinned:
                state = .pinned(content) // explicit tabs switch content without unpinning
            default:
                state = .expanded(content)
            }

        case .dismiss:
            switch state {
            case .pinned, .editing:
                break // pinned/editing require explicit unpin/endEditing
            default:
                state = .compact
            }

        case .pin:
            if let content = state.content ?? defaultContent(for: state) {
                state = .pinned(content)
            }

        case .unpin:
            if case .pinned(let content) = state {
                state = .expanded(content)
            }

        case .beginEditing:
            interruptedState = state
            state = .editing

        case .endEditing:
            state = interruptedState ?? .compact
            interruptedState = nil

        case .event(let event):
            handleEvent(event)

        case .eventExpired(let id):
            if activeTransientEventID == id {
                activeTransientEventID = nil
                state = interruptedState ?? .compact
                interruptedState = nil
            }

        case .autoCollapse:
            switch state {
            case .pinned, .editing:
                break
            default:
                state = .compact
            }
        }
        return state
    }

    private mutating func handleEvent(_ event: IslandEvent) {
        // Only interrupt for high/critical priority; low/normal events are
        // surfaced by the compact indicator without stealing the full state.
        guard event.priority >= .high else { return }
        // User-selected content always wins. An alert can take over only when
        // the island is idle; this prevents a notification from jumping tabs.
        switch state {
        case .compact, .hoverPreview:
            break
        default:
            return
        }
        interruptedState = state
        activeTransientEventID = event.id
        let content = event.payload.content ?? .notification
        state = .expanded(content)
    }

    private func defaultContent(for state: IslandPresentationState) -> IslandContent? {
        state.content
    }
}
