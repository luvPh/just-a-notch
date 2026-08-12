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
    @Published var hovering = false { didSet { scheduleTransportReveal() } }
    /// The ◀ ⏯ ▶ transport is revealed only after the pointer has rested on the
    /// island for `transportRevealDelay`; it hides immediately on leave.
    @Published private(set) var transportVisible = false
    private var transportWork: DispatchWorkItem?
    let transportRevealDelay: TimeInterval = 0.75
    /// "Up Next" / playlist panel for the playing source (YouTube).
    @Published var showList = false
    /// True khi tab đang mở là Lịch — panel cần chiều cao lớn hơn player.
    @Published var panelWantsTall = false
    /// Cây shortcut cho tab Files.
    let fileStore = FileShortcutStore()
    /// Clipboard history store backing the Clipboard tab.
    let clipboard = ClipboardStore()
    /// Pomodoro/plain countdown timer backing the Timer tab.
    lazy var timer: TimerService = {
        let s = AppSettings.shared
        return TimerService(config: { s.pomodoroConfig },
                            autoStartNext: { s.pomoAutoStart },
                            defaultSound: { s.timerSoundName },
                            chime: { [weak s] name in
                                guard let s, s.timerSoundEnabled else { return }
                                SoundLibrary.shared.play(name, volume: Float(s.timerVolume))
                            })
    }()
    /// True khi người dùng bấm ⤢ để phóng to panel Files. Ghi nhớ qua UserDefaults.
    @Published var filesExpanded: Bool = UserDefaults.standard.bool(forKey: "filesExpanded") {
        didSet { UserDefaults.standard.set(filesExpanded, forKey: "filesExpanded") }
    }
    /// Panel Files đang mở? (do NotchRootView set khi railTab == .files)
    @Published var filesTabActive = false
    /// Số favorite đang chọn ở tab Files nhỏ — hiển thị ở wing trái (FilesPanel cập nhật).
    @Published var filesSelCount = 0
    /// Người dùng bấm nút ghim (📌) để GIỮ notch mở dù bấm ra ngoài — cho kéo-thả
    /// ở dạng nhỏ. Ghi nhớ qua UserDefaults.
    @Published var pinnedOpen: Bool = UserDefaults.standard.bool(forKey: "pinnedOpen") {
        didSet { UserDefaults.standard.set(pinnedOpen, forKey: "pinnedOpen") }
    }
    /// Panel Lịch đang mở? (do NotchRootView set khi railTab == .calendar)
    @Published var calTabActive = false
    /// Panel Notifications đang mở? (do NotchRootView set khi railTab == .notifications)
    @Published var notifTabActive = false
    /// True khi người dùng bấm ⤢ để phóng Lịch từ tuần → tháng. Ghi nhớ qua UserDefaults.
    @Published var calExpanded: Bool = UserDefaults.standard.bool(forKey: "calExpanded") {
        didSet { UserDefaults.standard.set(calExpanded, forKey: "calExpanded") }
    }
    /// Số hàng tuần của tháng đang xem (4–6). CalendarPanel cập nhật ⇒ panel co/giãn
    /// đúng theo chiều cao lưới, không thừa một hàng trống khi tháng chỉ có 5 tuần.
    @Published var calendarRows: Int = 6
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
            .sink { [weak self] in
                self?.playNotifSound()
                self?.showHUD($0)
            }.store(in: &bag)
    }

    /// Phát âm báo khi có thông báo mới (độc lập với chuông timer).
    private func playNotifSound() {
        let s = AppSettings.shared
        guard s.notifSoundEnabled, let snd = NSSound(named: s.notifSoundName) else { return }
        snd.volume = Float(s.notifVolume)
        snd.play()
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
    /// Must clear the physical camera core (notchHeight) AND leave room for the
    /// two-line banner body below it; a fixed 56 left only ~6pt for the text.
    var hudHeight: CGFloat { notchHeight + 48 }

    enum CompactState { case quiet, resting, reading }
    var compactState: CompactState {
        guard let track, Self.hasRealTitle(track) else { return .quiet }
        return titleReveal ? .reading : .resting
    }

    // MARK: Geometry (wings around the fixed camera core)

    // Symmetric wings while playing; the reading state only grows the LEFT wing
    // (the 150pt title expansion), keeping the right wing steady.
    var leftReveal: CGFloat {
        switch compactState { case .quiet: 10; case .resting: 40; case .reading: 150 }
    }
    var rightReveal: CGFloat {
        // Hovering the compact island reveals ◀ ⏯ ▶ in the right wing, so it
        // grows to fit the transport controls (the waveform lived here before).
        if hoverControls { return 106 }
        let base: CGFloat
        switch compactState { case .quiet: base = 10; case .resting: base = 40; case .reading: base = 40 }
        // Đồng hồ đếm ngược chiếm chỗ waveform ở wing phải → nới rộng để badge đủ chỗ.
        return timer.isRunning ? max(base, 42) : base
    }
    /// True once the delayed reveal has fired — the trigger for morphing the
    /// waveform into transport buttons and widening the right wing.
    var hoverControls: Bool { transportVisible }

    /// Arm/cancel the delayed transport reveal as hover state changes.
    private func scheduleTransportReveal() {
        transportWork?.cancel()
        let canShow = hovering && hasMedia && !expanded && !showingHUD
        if canShow {
            let work = DispatchWorkItem { [weak self] in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { self?.transportVisible = true }
            }
            transportWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + transportRevealDelay, execute: work)
        } else if transportVisible {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { transportVisible = false }
        }
    }
    var compactHeight: CGFloat { compactState == .quiet ? 38 : 40 }
    var compactWidth: CGFloat { leftReveal + coreWidth + rightReveal }
    /// Fixed marquee viewport for the title (left reading wing minus icon + pads).
    var titleViewport: CGFloat { 150 - 18 - 13 - 8 }

    // Expanded window. (Bề ngang gọn; chiều cao giữ nguyên.)
    let expandedWidth: CGFloat = 380
    let expandedHeight: CGFloat = 150
    // Taller window while the queue/playlist is open (list scrolls within).
    let listExpandedHeight: CGFloat = 340
    /// Chiều cao panel khi mở tab Lịch — co giãn theo số hàng tuần thực tế của tháng
    /// (mỗi hàng ~30px). 6 hàng = 322 (đủ chỗ, không cắt ngày); 5 hàng thấp hơn 30px…
    private let calendarRowSlot: CGFloat = 30
    private var calendarBaseHeight: CGFloat { 322 - 6 * calendarRowSlot }   // phần khung ngoài lưới
    var calendarExpandedHeight: CGFloat {
        calendarBaseHeight + CGFloat(min(max(calendarRows, 4), 6)) * calendarRowSlot
    }
    /// Chiều cao lớn nhất tab Lịch có thể cần (6 hàng) — dùng cho canvas cố định.
    var calendarMaxHeight: CGFloat { calendarBaseHeight + 6 * calendarRowSlot }
    /// Chiều cao panel Files khi bấm ⤢ (đủ chỗ cho nhiều hàng).
    let filesExpandedHeight: CGFloat = 340
    /// Bề ngang panel Files khi bấm ⤢ — mở rộng để làm việc chính với tab này.
    let filesExpandedWidth: CGFloat = 640
    /// Chiều cao canvas cố định lớn nhất — panel window phải đủ cao cho mọi state.
    var maxSurfaceHeight: CGFloat {
        max(expandedHeight, listExpandedHeight, calendarMaxHeight, filesExpandedHeight)
    }
    /// Bề ngang canvas cố định lớn nhất — panel window phải đủ rộng cho mọi state.
    var maxSurfaceWidth: CGFloat {
        max(expandedWidth, hudWidth, filesExpandedWidth)
    }

    var isListOpen: Bool { expanded && showList }

    /// Files đang mở rộng toàn chiều ngang (ẩn sidebar, làm việc chính với tab).
    var filesWide: Bool { expanded && filesTabActive && filesExpanded }

    /// KHÔNG thu notch khi bấm ra ngoài khi: Files wide (⤢) HOẶC người dùng bật ghim
    /// (📌). Còn lại (dạng nhỏ không ghim, tab khác) vẫn thu như cũ.
    var keepOpenOnOutsideClick: Bool { filesWide || (filesTabActive && pinnedOpen) }

    var surfaceWidth: CGFloat {
        if showingHUD { return hudWidth }
        if filesWide { return filesExpandedWidth }
        return expanded ? expandedWidth : compactWidth
    }
    var surfaceHeight: CGFloat {
        if showingHUD { return hudHeight }
        if !expanded { return compactHeight }
        if isListOpen { return listExpandedHeight }
        if filesTabActive { return filesExpanded ? filesExpandedHeight : expandedHeight }
        if calTabActive { return calExpanded ? calendarExpandedHeight : expandedHeight }
        if notifTabActive { return expandedHeight }   // 150px như tab mặc định
        if panelWantsTall { return calendarExpandedHeight }
        return expandedHeight
    }
    /// Keep the camera core centred on the notch: shift by half the reveal imbalance.
    /// HUD and expanded are both centred, so no shift.
    var centerXOffset: CGFloat { (expanded || showingHUD) ? 0 : (rightReveal - leftReveal) / 2 }

    var bottomRadius: CGFloat {
        if showingHUD { return 22 }
        return expanded ? 26 : (compactState == .quiet ? 10 : 14)
    }
    var topRadius: CGFloat { expanded ? 12 : 9 }

    /// Đặt bởi global hotkey (⌃⌥1/2/3) — NotchRootView phân giải theo danh sách tab
    /// đang hiển thị rồi tự xoá về nil. 1-based.
    @Published var pendingTabIndex: Int?

    // MARK: Actions
    func toggleExpanded() { expanded.toggle(); if expanded { clearHUD() } }
    func collapse() { expanded = false; showList = false; filesSelCount = 0 }
    /// Mở/đóng notch từ global hotkey — thu gọn đầy đủ khi đang mở.
    func toggleNotch() { if expanded { collapse() } else { expanded = true; clearHUD() } }
    /// Mở notch (nếu đang thu) và yêu cầu nhảy tới tab thứ `n` (1-based).
    func requestTab(_ n: Int) { if !expanded { expanded = true; clearHUD() }; pendingTabIndex = n }
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

    /// Activate an app by bundle id (used by both the HUD banner and the
    /// Notifications tab rows).
    func openApp(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Activate the app currently playing media (resolved from its localized
    /// name, since the media track carries no bundle id). Used by the media
    /// source icon in the compact wing and the artwork in the expanded player.
    /// Bring the playing source's window to the front. For YouTube this focuses
    /// the exact browser tab; for native players it activates the app.
    func openSourceMediaApp() {
        media.focusSource()
    }

    /// Activate the app that sent the current HUD notification, then clear it.
    func openSourceApp() {
        if let record = hudNotification { openApp(bundleId: record.bundleId) }
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
