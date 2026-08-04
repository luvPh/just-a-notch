import SwiftUI
import Combine

/// Bridges the real MediaService to the SwiftUI island and owns the interaction
/// state (hover / expanded). Geometry respects the physical camera core: content
/// lives in the left/right wings, never over the notch itself.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var track: MediaTrack?
    @Published var playback: PlaybackState = .unsupported
    @Published var expanded = false
    @Published var hovering = false
    /// Transient title reveal, shown briefly only when the track changes.
    @Published var titleReveal = false
    private var lastIdentity: String?
    private var titleResetWork: DispatchWorkItem?

    // Set by the window controller from the detected notch.
    @Published var coreWidth: CGFloat = 200
    /// Physical notch (camera) height — used as the quiet height and the expanded top inset.
    @Published var notchHeight: CGFloat = 38

    private let media: MediaServiceProtocol
    private var bag = Set<AnyCancellable>()

    init(media: MediaServiceProtocol) {
        self.media = media
        media.currentTrack.receive(on: RunLoop.main).sink { [weak self] track in
            self?.handleTrack(track)
        }.store(in: &bag)
        media.playbackState.receive(on: RunLoop.main).sink { [weak self] in self?.playback = $0 }.store(in: &bag)
    }

    private func handleTrack(_ track: MediaTrack?) {
        self.track = track
        let id = track.map { $0.sourceAppName + "|" + $0.title }
        if let id, id != lastIdentity {
            lastIdentity = id
            revealTitleTransiently()
        }
        if track == nil { lastIdentity = nil; titleReveal = false }
    }

    /// Reveal the title on a track change, hold long enough for the marquee to
    /// slide through the whole title, then settle back to resting.
    private func revealTitleTransiently() {
        titleResetWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { titleReveal = true }
        // Duration scales with title length so long titles finish scrolling before retract.
        let len = track?.title.count ?? 0
        let overflow = max(0, Double(len) * 7.0 - Double(titleViewport))
        let duration = 1.5 /*pre-slide hold*/ + overflow / 34.0 /*scroll*/ + 1.0 /*end hold*/
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { self?.titleReveal = false }
        }
        titleResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(9.0, duration), execute: work)
    }

    var hasMedia: Bool { track != nil }
    var isPlaying: Bool { playback == .playing }

    enum CompactState { case quiet, resting, reading }
    var compactState: CompactState {
        guard hasMedia else { return .quiet }
        return titleReveal ? .reading : .resting   // title only on track change, never on hover
    }

    // MARK: Geometry (wings around the fixed camera core)

    // Symmetric wings while playing; the reading state only grows the LEFT wing
    // (the 150pt title expansion), keeping the right wing steady.
    var leftReveal: CGFloat {
        switch compactState { case .quiet: 10; case .resting: 50; case .reading: 150 }
    }
    var rightReveal: CGFloat {
        switch compactState { case .quiet: 10; case .resting: 50; case .reading: 50 }
    }
    var compactHeight: CGFloat { compactState == .quiet ? 38 : 40 }
    var compactWidth: CGFloat { leftReveal + coreWidth + rightReveal }
    /// Fixed marquee viewport for the title (left reading wing minus icon + pads).
    var titleViewport: CGFloat { 150 - 18 - 13 - 8 }

    // Expanded window.
    let expandedWidth: CGFloat = 412
    let expandedHeight: CGFloat = 138

    var surfaceWidth: CGFloat { expanded ? expandedWidth : compactWidth }
    var surfaceHeight: CGFloat { expanded ? expandedHeight : compactHeight }
    /// Keep the camera core centred on the notch: shift by half the reveal imbalance.
    var centerXOffset: CGFloat { expanded ? 0 : (rightReveal - leftReveal) / 2 }

    var bottomRadius: CGFloat { expanded ? 26 : (compactState == .quiet ? 10 : 14) }
    var topRadius: CGFloat { expanded ? 12 : 9 }

    // MARK: Actions
    func toggleExpanded() { expanded.toggle() }
    func collapse() { expanded = false }
    func playPause() { media.playPause() }
    func next() { media.nextTrack() }
    func previous() { media.previousTrack() }
    func start() { media.start(); media.refresh() }
}
