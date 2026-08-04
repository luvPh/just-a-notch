import Foundation
import Combine

enum TabTransitionDirection: Equatable {
    case forward
    case backward
    case none
}

enum TabTransitionPhase: Equatable {
    case idle
    case outgoing
    case portal
    case incoming
}

enum TabTransitionTimeline {
    static let outgoingToPortal: TimeInterval = 0.08
    static let portalToIncoming: TimeInterval = 0.06
    static let incomingToIdle: TimeInterval = 0.18
}

struct TabTransitionState: Equatable {
    var source: IslandContent
    var target: IslandContent
    var direction: TabTransitionDirection
    var phase: TabTransitionPhase
}

struct TabTransitionReducer {
    private(set) var state: TabTransitionState

    init(initial: IslandContent) {
        state = TabTransitionState(
            source: initial,
            target: initial,
            direction: .none,
            phase: .idle
        )
    }

    @discardableResult
    mutating func request(target: IslandContent) -> TabTransitionState {
        let source = state.target
        let direction: TabTransitionDirection
        let phase: TabTransitionPhase

        if source == target {
            direction = .none
            phase = .idle
        } else if Self.order(of: source) < Self.order(of: target) {
            direction = .forward
            phase = .outgoing
        } else {
            direction = .backward
            phase = .outgoing
        }

        state = TabTransitionState(
            source: source,
            target: target,
            direction: direction,
            phase: phase
        )
        return state
    }

    private static func order(of content: IslandContent) -> Int {
        switch content {
        case .media: 0
        case .systemStatus: 1
        case .finderShelf: 2
        case .notification: 3
        }
    }
}

@MainActor
final class TabTransitionCoordinator: ObservableObject {
    @Published private(set) var state: TabTransitionState {
        didSet {
            if state != authoritativeState {
                state = authoritativeState
            }
        }
    }
    @Published private(set) var headerContent: IslandContent {
        didSet {
            if headerContent != authoritativeHeaderContent {
                headerContent = authoritativeHeaderContent
            }
        }
    }
    @Published private(set) var portalProgress: Double {
        didSet {
            if portalProgress != authoritativePortalProgress {
                portalProgress = authoritativePortalProgress
            }
        }
    }
    @Published private(set) var portalRequestID: UInt64 {
        didSet {
            if portalRequestID != authoritativePortalRequestID {
                portalRequestID = authoritativePortalRequestID
            }
        }
    }
    @Published private(set) var portalCancellationID: UInt64 {
        didSet {
            if portalCancellationID != authoritativePortalCancellationID {
                portalCancellationID = authoritativePortalCancellationID
            }
        }
    }

    var reduceMotion: Bool

    private var reducer: TabTransitionReducer
    private var transitionTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var authoritativeState: TabTransitionState
    private var authoritativeHeaderContent: IslandContent
    private var authoritativePortalProgress: Double
    private var authoritativePortalRequestID: UInt64
    private var authoritativePortalCancellationID: UInt64

    init(initial: IslandContent, reduceMotion: Bool = false) {
        let reducer = TabTransitionReducer(initial: initial)
        self.reducer = reducer
        state = reducer.state
        headerContent = initial
        portalProgress = 0
        portalRequestID = 0
        portalCancellationID = 0
        self.reduceMotion = reduceMotion
        authoritativeState = reducer.state
        authoritativeHeaderContent = initial
        authoritativePortalProgress = 0
        authoritativePortalRequestID = 0
        authoritativePortalCancellationID = 0
    }

    func request(target: IslandContent) {
        generation += 1
        let requestGeneration = generation
        transitionTask?.cancel()
        transitionTask = nil
        let hadActivePortal = authoritativePortalProgress > 0

        let transition = reducer.request(target: target)
        if transition.direction == .none || reduceMotion {
            let terminal = Self.terminalState(for: target)
            guard publishState(terminal, generation: requestGeneration) else { return }
            guard publishHeaderContent(target, generation: requestGeneration) else { return }
            guard publishPortalProgress(0, generation: requestGeneration) else { return }
            if hadActivePortal {
                _ = publishPortalCancellationID(
                    requestGeneration,
                    generation: requestGeneration
                )
            }
            return
        }

        guard publishState(transition, generation: requestGeneration) else { return }

        guard publishPortalRequestID(
            requestGeneration,
            generation: requestGeneration
        ) else { return }

        // Task 7 animates this target value over the 280ms portal duration.
        guard publishPortalProgress(1, generation: requestGeneration) else { return }

        transitionTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: Self.nanoseconds(
                        for: TabTransitionTimeline.outgoingToPortal
                    )
                )
            } catch {
                return
            }

            guard let self,
                  !Task.isCancelled,
                  self.generation == requestGeneration else { return }
            guard self.publishState(
                Self.state(transition, phase: .portal),
                generation: requestGeneration
            ) else { return }
            guard self.publishHeaderContent(
                target,
                generation: requestGeneration
            ) else { return }

            do {
                try await Task.sleep(
                    nanoseconds: Self.nanoseconds(
                        for: TabTransitionTimeline.portalToIncoming
                    )
                )
            } catch {
                return
            }

            guard !Task.isCancelled,
                  self.generation == requestGeneration else { return }
            guard self.publishState(
                Self.state(transition, phase: .incoming),
                generation: requestGeneration
            ) else { return }

            do {
                try await Task.sleep(
                    nanoseconds: Self.nanoseconds(
                        for: TabTransitionTimeline.incomingToIdle
                    )
                )
            } catch {
                return
            }

            guard !Task.isCancelled,
                  self.generation == requestGeneration else { return }
            guard self.publishState(
                Self.terminalState(for: target),
                generation: requestGeneration
            ) else { return }
            guard self.publishPortalProgress(
                0,
                generation: requestGeneration
            ) else { return }
            guard !Task.isCancelled,
                  self.generation == requestGeneration else { return }
            self.transitionTask = nil
        }
    }

    @discardableResult
    private func publishState(
        _ newState: TabTransitionState,
        generation expectedGeneration: UInt64
    ) -> Bool {
        guard generation == expectedGeneration else { return false }
        authoritativeState = newState
        state = newState
        return generation == expectedGeneration
    }

    @discardableResult
    private func publishHeaderContent(
        _ newHeaderContent: IslandContent,
        generation expectedGeneration: UInt64
    ) -> Bool {
        guard generation == expectedGeneration else { return false }
        authoritativeHeaderContent = newHeaderContent
        headerContent = newHeaderContent
        return generation == expectedGeneration
    }

    @discardableResult
    private func publishPortalProgress(
        _ newPortalProgress: Double,
        generation expectedGeneration: UInt64
    ) -> Bool {
        guard generation == expectedGeneration else { return false }
        authoritativePortalProgress = newPortalProgress
        portalProgress = newPortalProgress
        return generation == expectedGeneration
    }

    @discardableResult
    private func publishPortalRequestID(
        _ requestID: UInt64,
        generation expectedGeneration: UInt64
    ) -> Bool {
        guard generation == expectedGeneration else { return false }
        authoritativePortalRequestID = requestID
        portalRequestID = requestID
        return generation == expectedGeneration
    }

    @discardableResult
    private func publishPortalCancellationID(
        _ requestID: UInt64,
        generation expectedGeneration: UInt64
    ) -> Bool {
        guard generation == expectedGeneration else { return false }
        authoritativePortalCancellationID = requestID
        portalCancellationID = requestID
        return generation == expectedGeneration
    }

    private static func state(
        _ transition: TabTransitionState,
        phase: TabTransitionPhase
    ) -> TabTransitionState {
        TabTransitionState(
            source: transition.source,
            target: transition.target,
            direction: transition.direction,
            phase: phase
        )
    }

    private static func terminalState(for target: IslandContent) -> TabTransitionState {
        TabTransitionState(
            source: target,
            target: target,
            direction: .none,
            phase: .idle
        )
    }

    private static func nanoseconds(for duration: TimeInterval) -> UInt64 {
        UInt64(duration * 1_000_000_000)
    }
}
