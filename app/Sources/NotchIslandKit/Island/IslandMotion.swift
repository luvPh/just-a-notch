import AppKit
import Combine

enum IslandMotion {
    static let wingWidth: CGFloat = 83
    static let quietReveal: CGFloat = 12
    static let fallbackCoreWidth: CGFloat = 200
    // Asymmetric compact reveals (see asymmetric-compact-notch spec).
    static let restLeftReveal: CGFloat = 44
    static let restRightReveal: CGFloat = 76
    static let readingLeftReveal: CGFloat = 156
    static let expansionOvershoot: CGFloat = 18
    static let collapseAnticipationWidth: CGFloat = 6
    static let collapseAnticipationHeight: CGFloat = 2

    static let expansionDuration: TimeInterval = 0.26
    static let collapseAnticipationDuration: TimeInterval = 0.08
    static let collapseDuration: TimeInterval = 0.24
    static let traceDuration: TimeInterval = 0.65
    static let pauseSettleDuration: TimeInterval = 0.18

    static let tabIndicatorDuration: TimeInterval = 0.22
    static let tabOutgoingDuration: TimeInterval = 0.14
    static let tabPortalDuration: TimeInterval = 0.28
    static let tabIncomingDuration: TimeInterval = 0.24
    static let tabOverlap: TimeInterval = 0.06
    static let reducedMotionFade: TimeInterval = 0.16
}

enum CompactContentState: Equatable {
    case quiet
    case active
}

struct CompactGeometry: Equatable {
    let coreWidth: CGFloat
    let surfaceWidth: CGFloat
    let leftWing: Range<CGFloat>
    let core: Range<CGFloat>
    let rightWing: Range<CGFloat>
}

enum CompactGeometryModel {
    static func layout(coreWidth: CGFloat?, state: CompactContentState) -> CompactGeometry {
        let coreWidth = max(0, coreWidth ?? IslandMotion.fallbackCoreWidth)
        let reveal = state == .active ? IslandMotion.wingWidth : IslandMotion.quietReveal
        let surfaceWidth = coreWidth + reveal * 2

        return CompactGeometry(
            coreWidth: coreWidth,
            surfaceWidth: surfaceWidth,
            leftWing: 0..<reveal,
            core: reveal..<(reveal + coreWidth),
            rightWing: (reveal + coreWidth)..<surfaceWidth
        )
    }
}

/// Named presentation states for the asymmetric compact surface. The physical
/// camera core is the anchor; only the left reveal expands for the reading
/// reveal, so the core never moves.
enum CompactPresentationState: Equatable {
    case quiet
    case mediaResting
    case mediaReading
}

/// Resolved asymmetric geometry: explicit left/right reveals around a fixed
/// core. Origin is derived from the core centre, not the total surface centre.
struct AsymmetricCompactGeometry: Equatable {
    let coreWidth: CGFloat
    let leftReveal: CGFloat
    let rightReveal: CGFloat

    var totalWidth: CGFloat { leftReveal + coreWidth + rightReveal }

    /// Left-origin ranges within the composed surface.
    var leftWing: Range<CGFloat> { 0..<leftReveal }
    var core: Range<CGFloat> { leftReveal..<(leftReveal + coreWidth) }
    var rightWing: Range<CGFloat> { (leftReveal + coreWidth)..<totalWidth }

    /// Panel frame origin X that keeps the physical core centred on `coreCentreX`.
    func panelOriginX(coreCentreX: CGFloat) -> CGFloat {
        coreCentreX - coreWidth / 2 - leftReveal
    }
}

enum AsymmetricCompactGeometryModel {
    static func geometry(coreWidth: CGFloat?,
                         state: CompactPresentationState) -> AsymmetricCompactGeometry {
        let core = max(0, coreWidth ?? IslandMotion.fallbackCoreWidth)
        let left: CGFloat
        let right: CGFloat
        switch state {
        case .quiet:
            left = IslandMotion.quietReveal
            right = IslandMotion.quietReveal
        case .mediaResting:
            left = IslandMotion.restLeftReveal
            right = IslandMotion.restRightReveal
        case .mediaReading:
            left = IslandMotion.readingLeftReveal
            right = IslandMotion.restRightReveal
        }
        return AsymmetricCompactGeometry(coreWidth: core, leftReveal: left, rightReveal: right)
    }

    /// Core-anchored panel origin X. `coreCentreX = screenMidX + alignmentOffset`.
    static func panelOriginX(screenMidX: CGFloat,
                             alignmentOffset: CGFloat,
                             geometry: AsymmetricCompactGeometry) -> CGFloat {
        geometry.panelOriginX(coreCentreX: screenMidX + alignmentOffset)
    }
}

enum IslandMotionPhase: Equatable {
    case resting
    case expanding
    case settled
    case anticipatingClose
    case collapsing
}

enum IslandMotionEvent {
    case expandRequested
    case expansionSettled
    case collapseRequested
    case anticipationFinished
    case collapseFinished
}

struct IslandMotionReducer {
    private(set) var phase: IslandMotionPhase

    init(phase: IslandMotionPhase = .resting) {
        self.phase = phase
    }

    @discardableResult
    mutating func handle(_ event: IslandMotionEvent) -> IslandMotionPhase {
        switch event {
        case .expandRequested:
            phase = .expanding
        case .expansionSettled:
            phase = .settled
        case .collapseRequested:
            phase = .anticipatingClose
        case .anticipationFinished:
            phase = .collapsing
        case .collapseFinished:
            phase = .resting
        }

        return phase
    }
}

@MainActor
final class IslandMotionCoordinator: ObservableObject {
    @Published private(set) var phase: IslandMotionPhase {
        didSet {
            if phase != reducer.phase {
                phase = reducer.phase
            }
        }
    }
    @Published private(set) var geometry: CompactGeometry {
        didSet {
            let latestGeometry = CompactGeometryModel.layout(
                coreWidth: coreWidth,
                state: compactContentState
            )
            if geometry != latestGeometry {
                geometry = latestGeometry
            }
        }
    }
    @Published private(set) var isExpandedTarget: Bool {
        didSet {
            if isExpandedTarget != requestedExpandedTarget {
                isExpandedTarget = requestedExpandedTarget
            }
        }
    }
    var reduceMotion: Bool

    /// Asymmetric, core-anchored compact geometry driven by the reading reducer.
    @Published private(set) var asymmetricGeometry: AsymmetricCompactGeometry
    /// Current compact reading lifecycle (identity, reading vs resting phase).
    @Published private(set) var readingState: CompactReadingState = .initial

    private var reducer: IslandMotionReducer
    private var animationTask: Task<Void, Never>?
    private var readingTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var requestedExpandedTarget: Bool
    private var coreWidth: CGFloat?
    private var compactContentState: CompactContentState

    init(
        coreWidth: CGFloat? = nil,
        compactContentState: CompactContentState = .quiet,
        reduceMotion: Bool = false
    ) {
        let reducer = IslandMotionReducer()
        self.reducer = reducer
        phase = reducer.phase
        geometry = CompactGeometryModel.layout(
            coreWidth: coreWidth,
            state: compactContentState
        )
        isExpandedTarget = false
        requestedExpandedTarget = false
        self.reduceMotion = reduceMotion
        self.coreWidth = coreWidth
        self.compactContentState = compactContentState
        asymmetricGeometry = AsymmetricCompactGeometryModel.geometry(
            coreWidth: coreWidth,
            state: compactContentState == .quiet ? .quiet : .mediaResting
        )
    }

    /// The fixed compact "envelope" the window is sized to. It stays at the
    /// widest (reading) reveal while media is present so the AppKit window never
    /// resizes during the reading reveal — the left wing animates entirely inside
    /// SwiftUI, which keeps the open/close motion smooth and the core stationary.
    var compactEnvelopeGeometry: AsymmetricCompactGeometry {
        let hasMedia = readingState.identity != nil
        return AsymmetricCompactGeometryModel.geometry(
            coreWidth: coreWidth,
            state: hasMedia ? .mediaReading : .quiet)
    }

    /// Feed a media identity (`sourceApp + "|" + title`, or nil) plus the reading
    /// window to display it for. A new identity opens the reading reveal and
    /// schedules the shrink back to resting; unchanged identities are ignored.
    /// This coordinator owns only compact reveal state — it never selects tabs.
    func updateMediaIdentity(_ identity: String?, readingWindow: TimeInterval) {
        let previous = readingState
        readingState = CompactReadingReducer.reduce(previous, .mediaUpdate(identity: identity))
        recalculateAsymmetricGeometry()
        guard readingState.generation != previous.generation,
              readingState.phase == .reading else {
            return
        }
        scheduleReadingShrink(generation: readingState.generation, after: readingWindow)
    }

    private func scheduleReadingShrink(generation: Int, after window: TimeInterval) {
        readingTask?.cancel()
        guard !reduceMotion else {
            // Reduce Motion: still hold the static reveal for the reading window,
            // then shrink immediately (no marquee/animation in the view).
            readingTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.nanoseconds(for: window))
                guard let self, !Task.isCancelled else { return }
                self.finishReading(generation: generation)
            }
            return
        }
        readingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: window))
            guard let self, !Task.isCancelled else { return }
            self.finishReading(generation: generation)
        }
    }

    private func finishReading(generation: Int) {
        readingState = CompactReadingReducer.reduce(
            readingState, .readingIntervalElapsed(generation: generation))
        recalculateAsymmetricGeometry()
    }

    private func recalculateAsymmetricGeometry() {
        asymmetricGeometry = AsymmetricCompactGeometryModel.geometry(
            coreWidth: coreWidth,
            state: readingState.presentationState
        )
    }

    func requestExpanded(_ expanded: Bool) {
        generation += 1
        let requestGeneration = generation
        animationTask?.cancel()
        animationTask = nil
        requestedExpandedTarget = expanded
        isExpandedTarget = expanded
        guard generation == requestGeneration else { return }

        if expanded {
            guard transition(.expandRequested, generation: requestGeneration) else { return }

            if reduceMotion {
                _ = transition(.expansionSettled, generation: requestGeneration)
                return
            }

            animationTask = Task { [weak self] in
                do {
                    try await Task.sleep(
                        nanoseconds: Self.nanoseconds(for: IslandMotion.expansionDuration)
                    )
                } catch {
                    return
                }

                guard let self,
                      !Task.isCancelled,
                      self.generation == requestGeneration else { return }
                guard self.transition(
                    .expansionSettled,
                    generation: requestGeneration
                ) else { return }
                guard !Task.isCancelled,
                      self.generation == requestGeneration else { return }
                self.animationTask = nil
            }
        } else {
            guard transition(.collapseRequested, generation: requestGeneration) else { return }

            if reduceMotion {
                _ = transition(.collapseFinished, generation: requestGeneration)
                return
            }

            animationTask = Task { [weak self] in
                do {
                    try await Task.sleep(
                        nanoseconds: Self.nanoseconds(
                            for: IslandMotion.collapseAnticipationDuration
                        )
                    )
                } catch {
                    return
                }

                guard let self,
                      !Task.isCancelled,
                      self.generation == requestGeneration else { return }
                guard self.transition(
                    .anticipationFinished,
                    generation: requestGeneration
                ) else { return }

                do {
                    try await Task.sleep(
                        nanoseconds: Self.nanoseconds(for: IslandMotion.collapseDuration)
                    )
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      self.generation == requestGeneration else { return }
                guard self.transition(
                    .collapseFinished,
                    generation: requestGeneration
                ) else { return }
                guard !Task.isCancelled,
                      self.generation == requestGeneration else { return }
                self.animationTask = nil
            }
        }
    }

    func setCoreWidth(_ coreWidth: CGFloat?) {
        self.coreWidth = coreWidth
        recalculateGeometry()
    }

    func setCompactContentState(_ state: CompactContentState) {
        compactContentState = state
        recalculateGeometry()
    }

    @discardableResult
    private func transition(
        _ event: IslandMotionEvent,
        generation expectedGeneration: UInt64
    ) -> Bool {
        guard generation == expectedGeneration else { return false }
        phase = reducer.handle(event)
        return generation == expectedGeneration
    }

    private func recalculateGeometry() {
        geometry = CompactGeometryModel.layout(
            coreWidth: coreWidth,
            state: compactContentState
        )
        recalculateAsymmetricGeometry()
    }

    private static func nanoseconds(for duration: TimeInterval) -> UInt64 {
        UInt64(duration * 1_000_000_000)
    }
}
