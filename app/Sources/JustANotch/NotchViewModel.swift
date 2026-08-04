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
    @Published var menuBarHeight: CGFloat = 32

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

    /// Show the title for ~2.6s on a track change, then settle back to resting.
    private func revealTitleTransiently() {
        titleResetWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { titleReveal = true }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { self?.titleReveal = false }
        }
        titleResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    var hasMedia: Bool { track != nil }
    var isPlaying: Bool { playback == .playing }

    enum CompactState { case quiet, resting, reading }
    var compactState: CompactState {
        guard hasMedia else { return .quiet }
        return titleReveal ? .reading : .resting   // title only on track change, never on hover
    }

    // MARK: Geometry (wings around the fixed camera core)

    var leftReveal: CGFloat {
        switch compactState { case .quiet: 0; case .resting: 46; case .reading: 168 }
    }
    var rightReveal: CGFloat {
        switch compactState { case .quiet: 0; case .resting: 66; case .reading: 66 }
    }
    var compactHeight: CGFloat { compactState == .quiet ? menuBarHeight : menuBarHeight + 6 }
    var compactWidth: CGFloat { leftReveal + coreWidth + rightReveal }

    // Expanded (Media-only for now).
    let expandedWidth: CGFloat = 384
    var expandedHeight: CGFloat { menuBarHeight + 150 }

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
