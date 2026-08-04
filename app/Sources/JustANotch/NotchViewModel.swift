import SwiftUI
import Combine
import AppKit

/// Bridges the real MediaService to the SwiftUI island and owns the interaction
/// state (hover / expanded). Geometry respects the physical camera core: content
/// lives in the left/right wings, never over the notch itself.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var track: MediaTrack?
    @Published var playback: PlaybackState = .unsupported
    @Published var expanded = false
    @Published var hovering = false
    /// "Up Next" / playlist panel for the playing source (YouTube).
    @Published var showList = false
    @Published var playlist: [MediaListItem] = []
    /// Transient title reveal, shown briefly only when the track changes.
    @Published var titleReveal = false

    // MARK: Notifications
    /// Banner currently popped over the compact surface, or nil.
    @Published var hudNotification: NotificationRecord?
    /// Retained history (newest first) for the Notifications tab.
    @Published var notifications: [NotificationRecord] = []
    /// True when the Notification Center DB can't be read (needs Full Disk Access).
    @Published var notificationsPermissionDenied = false
    private var hudClearWork: DispatchWorkItem?
    let hudDuration: TimeInterval = 4
    private var lastIdentity: String?
    private var titleResetWork: DispatchWorkItem?
    let titleEntranceDuration: TimeInterval = 0.42

    // Set by the window controller from the detected notch.
    @Published var coreWidth: CGFloat = 200
    /// Physical notch (camera) height — used as the quiet height and the expanded top inset.
    @Published var notchHeight: CGFloat = 38

    private let media: MediaServiceProtocol
    private let notifier: NotificationServiceProtocol
    private var bag = Set<AnyCancellable>()

    init(media: MediaServiceProtocol, notifier: NotificationServiceProtocol) {
        self.media = media
        self.notifier = notifier
        media.currentTrack.receive(on: RunLoop.main).sink { [weak self] track in
            self?.handleTrack(track)
        }.store(in: &bag)
        media.playbackState.receive(on: RunLoop.main).sink { [weak self] in self?.playback = $0 }.store(in: &bag)

        notifier.history.receive(on: RunLoop.main)
            .sink { [weak self] in self?.notifications = $0 }.store(in: &bag)
        notifier.permissionState.receive(on: RunLoop.main)
            .sink { [weak self] in self?.notificationsPermissionDenied = ($0 == .denied) }.store(in: &bag)
        notifier.latestArrival.receive(on: RunLoop.main)
            .sink { [weak self] in self?.showHUD($0) }.store(in: &bag)
    }

    private func handleTrack(_ track: MediaTrack?) {
        self.track = track
        let id = track.map { $0.sourceAppName + "|" + $0.title }
        if let id, id != lastIdentity {
            lastIdentity = id
            // Only pop the title open once we actually have a real name — while a
            // new video is still loading the source can report an empty / "YouTube"
            // placeholder, and we don't want the wing to expand onto a blank title.
            if let track, Self.hasRealTitle(track) { revealTitleTransiently() }
        }
        if track == nil { lastIdentity = nil; titleReveal = false }
    }

    private static func hasRealTitle(_ track: MediaTrack) -> Bool {
        let t = track.title.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.caseInsensitiveCompare("YouTube") != .orderedSame
    }

    /// Reveal the title on a track change, hold long enough for the marquee to
    /// slide through the whole title, then settle back to resting.
    private func revealTitleTransiently() {
        titleResetWork?.cancel()
        withAnimation(.spring(response: titleEntranceDuration, dampingFraction: 0.8)) { titleReveal = true }
    }

    /// Called after the marquee has measured its actual overflow, so the wing
    /// cannot retract before the last characters have been shown.
    func scheduleTitleRetraction(afterPan panDuration: TimeInterval) {
        guard titleReveal else { return }
        titleResetWork?.cancel()
        let timing = TitleRevealTiming(pan: panDuration)
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { self?.titleReveal = false }
        }
        titleResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.retractionDelay, execute: work)
    }

    var hasMedia: Bool { track != nil }
    var isPlaying: Bool { playback == .playing }

    /// The HUD takes over the compact surface while a banner is showing and the
    /// panel is not expanded.
    var showingHUD: Bool { hudNotification != nil && !expanded }
    let hudWidth: CGFloat = 412
    let hudHeight: CGFloat = 56

    enum CompactState { case quiet, resting, reading }
    var compactState: CompactState {
        guard let track, Self.hasRealTitle(track) else { return .quiet }
        return titleReveal ? .reading : .resting
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
    let expandedHeight: CGFloat = 150
    // Taller window while the queue/playlist is open (list scrolls within).
    let listExpandedHeight: CGFloat = 340

    var isListOpen: Bool { expanded && showList }

    var surfaceWidth: CGFloat {
        if showingHUD { return hudWidth }
        return expanded ? expandedWidth : compactWidth
    }
    var surfaceHeight: CGFloat {
        if showingHUD { return hudHeight }
        return isListOpen ? listExpandedHeight : (expanded ? expandedHeight : compactHeight)
    }
    /// Keep the camera core centred on the notch: shift by half the reveal imbalance.
    /// HUD and expanded are both centred, so no shift.
    var centerXOffset: CGFloat { (expanded || showingHUD) ? 0 : (rightReveal - leftReveal) / 2 }

    var bottomRadius: CGFloat {
        if showingHUD { return 22 }
        return expanded ? 26 : (compactState == .quiet ? 10 : 14)
    }
    var topRadius: CGFloat { expanded ? 12 : 9 }

    // MARK: Actions
    func toggleExpanded() { expanded.toggle() }
    func collapse() { expanded = false; showList = false }
    /// Pull the latest media state now (e.g. right as the panel opens).
    func refreshMedia() { media.refresh() }

    /// Icon for a notification's source app (delegates to the service cache).
    func notificationIcon(_ bundleId: String) -> NSImage { notifier.icon(forBundle: bundleId) }

    /// Grouped history for the Notifications tab.
    var notificationGroups: [NotificationGroup] { groupByApp(notifications) }

    /// Pop a HUD banner; latest arrival replaces any current one (no queue).
    /// Suppressed while expanded so it doesn't fight the open player.
    private func showHUD(_ record: NotificationRecord) {
        guard !expanded else { return }
        hudClearWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { hudNotification = record }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { self?.hudNotification = nil }
        }
        hudClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hudDuration, execute: work)
    }

    /// Activate the app that sent the current HUD notification, then clear it.
    func openSourceApp() {
        guard let record = hudNotification,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleId) else {
            clearHUD(); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        clearHUD()
    }

    func clearHUD() {
        hudClearWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { hudNotification = nil }
    }

    /// Toggle the queue panel; (re)fetch the list whenever it opens.
    func toggleList() {
        showList.toggle()
        if showList { refreshList() }
    }
    func refreshList() {
        media.fetchPlaylist { [weak self] items in self?.playlist = items }
    }
    func playListItem(_ item: MediaListItem) {
        media.play(item: item)
        // Optimistic: reflect the new current row until the next poll/refresh.
        playlist = playlist.map { var m = $0; m.isCurrent = (m.id == item.id); return m }
    }
    func playPause() { media.playPause() }
    func next() { media.nextTrack() }
    func previous() { media.previousTrack() }
    func seek(toFraction fraction: Double) { media.seek(toFraction: fraction) }
    func start() { media.start(); media.refresh(); notifier.start() }
}
