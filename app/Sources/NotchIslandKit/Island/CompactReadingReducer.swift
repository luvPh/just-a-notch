// File: Sources/NotchIslandKit/Island/CompactReadingReducer.swift
import Foundation

/// Pure reducer owning the compact media reading lifecycle: current identity,
/// reading vs resting phase, and a monotonically increasing generation used as
/// a retarget / cancellation token. It never selects tabs or mutates global
/// island state — the shell and tab coordinators keep that ownership.
struct CompactReadingState: Equatable {
    enum Phase: Equatable {
        case resting
        case reading
    }

    /// `sourceAppName + "|" + title`, or nil when no media is present.
    var identity: String?
    var phase: Phase
    /// Bumped on every new identity; a `.readingIntervalElapsed` carrying an
    /// older generation is a stale timer and is ignored.
    var generation: Int
    /// True only on the state produced when a new identity opens the reading
    /// reveal — the one moment sweep / trace / waveform-settle may run.
    var allowsOneShotAccents: Bool

    static let initial = CompactReadingState(
        identity: nil, phase: .resting, generation: 0, allowsOneShotAccents: false)

    var presentationState: CompactPresentationState {
        switch phase {
        case .reading:
            return .mediaReading
        case .resting:
            return identity == nil ? .quiet : .mediaResting
        }
    }
}

enum CompactReadingEvent: Equatable {
    /// A media poll result. `nil` identity means media went away.
    case mediaUpdate(identity: String?)
    /// The reading window for `generation` finished; shrink back to resting.
    case readingIntervalElapsed(generation: Int)
}

enum CompactReadingReducer {
    static func reduce(_ state: CompactReadingState,
                       _ event: CompactReadingEvent) -> CompactReadingState {
        var next = state
        next.allowsOneShotAccents = false

        switch event {
        case .mediaUpdate(let identity):
            guard let identity else {
                next.identity = nil
                next.phase = .resting
                return next
            }
            if identity == state.identity {
                // Unchanged poll: do not restart reading, do not replay accents.
                return next
            }
            // New identity: retarget immediately from the current presentation.
            next.identity = identity
            next.phase = .reading
            next.generation = state.generation + 1
            next.allowsOneShotAccents = true
            return next

        case .readingIntervalElapsed(let generation):
            guard generation == state.generation, state.phase == .reading else {
                // Stale timer from a superseded identity, or already resting.
                return next
            }
            next.phase = .resting
            return next
        }
    }
}
