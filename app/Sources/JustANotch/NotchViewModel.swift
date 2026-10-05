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
    @Published var expanded = false {
        didSet { if expanded { closeLauncher() }; noteInteraction() }
    }
    @Published var hovering = false {
        didSet {
            if !hovering { hideTransport() }
            scheduleLauncherReveal()
            noteInteraction()
        }
    }
    /// ◀ ⏯ ▶ hiện khi BẤM vào soundwave (không còn tự hiện khi hover); chuột rời
    /// notch thì thu về soundwave.
    @Published private(set) var transportVisible = false
    /// "Up Next" / playlist panel for the playing source (YouTube).
    @Published var showList = false
    /// True khi tab đang mở là Lịch — panel cần chiều cao lớn hơn player.
    @Published var panelWantsTall = false
    /// Cây shortcut cho tab Files.
    let fileStore = FileShortcutStore()
    /// Clipboard history store backing the Clipboard tab.
    let clipboard = ClipboardStore()
    let learn = LearnStore.shared
    /// Kệ giữ tạm file kéo-thả (chỉ trong phiên).
    let shelf = ShelfStore()
    /// Ba đồng hồ ĐỘC LẬP, mỗi trang carousel một cái, chạy song song được:
    /// Đơn/stopwatch, Pomodoro, Chuỗi tự tạo.
    lazy var timerSingle: TimerService = Self.makeTimer()
    lazy var timerPomodoro: TimerService = Self.makeTimer()
    lazy var timerSequence: TimerService = Self.makeTimer()

    private static func makeTimer() -> TimerService {
        let s = AppSettings.shared
        return TimerService(config: { s.pomodoroConfig },
                            autoStartNext: { s.pomoAutoStart },
                            defaultSound: { s.timerSoundName },
                            chime: { [weak s] name in
                                guard let s, s.timerSoundEnabled else { return }
                                SoundLibrary.shared.play(name, volume: Float(s.timerVolume))
                            })
    }

    /// Đồng hồ dùng để hiển thị badge/đếm ngược ở wing: ưu tiên cái đang chạy.
    var displayTimer: TimerService {
        if timerPomodoro.isRunning { return timerPomodoro }
        if timerSingle.isRunning { return timerSingle }
        if timerSequence.isRunning { return timerSequence }
        return timerPomodoro
    }
    var anyTimerRunning: Bool {
        timerSingle.isRunning || timerPomodoro.isRunning || timerSequence.isRunning
    }
    /// True khi người dùng bấm ⤢ để phóng to panel Files. Ghi nhớ qua UserDefaults.
    @Published var filesExpanded: Bool = UserDefaults.standard.bool(forKey: "filesExpanded") {
        didSet {
            UserDefaults.standard.set(filesExpanded, forKey: "filesExpanded")
            noteInteraction()
        }
    }
    /// Panel Files đang mở? (do NotchRootView set khi railTab == .files)
    @Published var filesTabActive = false
    /// Tab Clipboard đang mở → notch rộng/cao hơn cho dải thẻ.
    @Published var clipTabActive = false
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
        didSet {
            UserDefaults.standard.set(calExpanded, forKey: "calExpanded")
            noteInteraction()
        }
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
    private var autoShrinkWork: DispatchWorkItem?
    let hudDuration: TimeInterval = 4
    private var lastIdentity: String?
    private var titleResetWork: DispatchWorkItem?
    let titleEntranceDuration: TimeInterval = 0.42

    // MARK: Shelf (kệ giữ tạm)
    /// Shelf đang bung trên bề mặt notch (do kéo file vào hoặc hover khi có file).
    /// Thu sau 1s khi chuột rời hover.
    @Published var shelfActive = false
    private var shelfHideWork: DispatchWorkItem?
    /// Hẹn bung shelf khi nhấc file (dwell) — xem `shelfOpenDelay`.
    private var shelfShowWork: DispatchWorkItem?
    /// Nhấc file lên rồi phải giữ cú kéo đủ lâu mới bung kệ — tránh kệ nháy ra
    /// mỗi lần kéo-thả nhanh trong Finder mà không có ý định dùng notch.
    private let shelfOpenDelay: TimeInterval = 2
    let shelfWidth: CGFloat = 600
    /// Lưới 6 cột/hàng; cao 150 cho 1 hàng, phình thêm mỗi hàng, tối đa 2 hàng.
    private let shelfRowExtra: CGFloat = 86
    var shelfRows: Int {
        guard !shelf.isEmpty else { return 1 }
        return min(2, (shelf.count + 5) / 6)
    }
    var shelfHeight: CGFloat { 150 + CGFloat(shelfRows - 1) * shelfRowExtra }

    /// Có cú kéo file đang diễn ra ở đâu đó trên hệ thống. Khi bật, shelf được
    /// giữ mở làm đích thả và KHÔNG bị hẹn thu dù con trỏ chưa vào notch.
    @Published var systemFileDragActive = false

    /// Nhấc file ở bất kỳ đâu ⇒ hẹn bung kệ sau `shelfOpenDelay` (nếu cú kéo còn).
    /// Kéo thẳng lên notch vẫn bung ngay (hover/dragEnter gọi `presentShelf`).
    func beginSystemFileDrag() {
        guard !expanded else { return }
        systemFileDragActive = true
        scheduleShelfShow()
    }

    /// Hẹn bung kệ; huỷ nếu cú kéo kết thúc trước hạn.
    private func scheduleShelfShow() {
        guard shelfShowWork == nil, !shelfActive else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            shelfShowWork = nil
            guard systemFileDragActive, !expanded else { return }
            presentShelf()
        }
        shelfShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + shelfOpenDelay, execute: work)
    }
    private func cancelShelfShow() { shelfShowWork?.cancel(); shelfShowWork = nil }

    /// Nhả chuột ⇒ hết cú kéo; kệ thu như bình thường nếu con trỏ không ở trên notch.
    func endSystemFileDrag() {
        cancelShelfShow()
        guard systemFileDragActive else { return }
        systemFileDragActive = false
        if shelfActive { scheduleShelfHide() }
    }

    /// Bung shelf.
    func presentShelf() {
        cancelShelfShow()
        cancelShelfHide()
        clearHUD()
        shelfActive = true
    }
    /// Hẹn thu shelf sau 1s (gọi khi chuột rời hover). Chỉ hẹn một lần.
    func scheduleShelfHide() {
        guard shelfHideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.shelfActive = false
            self?.shelfHideWork = nil
        }
        shelfHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
    func cancelShelfHide() { shelfHideWork?.cancel(); shelfHideWork = nil }
    func dismissShelf() { cancelShelfShow(); cancelShelfHide(); shelfActive = false }
    /// Notch đóng + đang giữ file → tô ánh sáng chạy viền mời hover.
    var shelfGlowing: Bool {
        !shelfActive && !expanded && !showingHUD && !shelf.isEmpty
    }

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
            .sink { [weak self] in self?.notifications = Self.dropClaude($0) }.store(in: &bag)
        notifier.permissionState.receive(on: RunLoop.main)
            .sink { [weak self] in self?.notificationsPermissionDenied = ($0 == .denied) }.store(in: &bag)
        notifier.latestArrival.receive(on: RunLoop.main)
            .filter { !(AppSettings.shared.claudeOn && ClaudeNotificationFilter.isClaude($0)) }
            .sink { [weak self] in
                self?.playNotifSound()
                self?.showHUD($0)
            }.store(in: &bag)
    }

    /// Bật theo dõi Claude trên notch → bỏ thông báo hệ thống của Claude (tránh báo trùng).
    private static func dropClaude(_ list: [NotificationRecord]) -> [NotificationRecord] {
        AppSettings.shared.claudeOn ? list.filter { !ClaudeNotificationFilter.isClaude($0) } : list
    }

    /// Phát âm báo khi có thông báo mới (độc lập với chuông timer).
    private func playNotifSound() {
        let s = AppSettings.shared
        guard s.notifSoundEnabled else { return }
        SoundLibrary.shared.play(s.notifSoundName, volume: Float(s.notifVolume))
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
    var showingHUD: Bool { hudNotification != nil && !expanded && !shelfActive }
    let hudWidth: CGFloat = 412
    /// Must clear the physical camera core (notchHeight) AND leave room for the
    /// two-line banner body below it; a fixed 56 left only ~6pt for the text.
    var hudHeight: CGFloat { notchHeight + 48 }

    enum CompactState { case quiet, resting, reading }
    var compactState: CompactState {
        guard let track, Self.hasRealTitle(track) else { return .quiet }
        // Launcher đang mở → thu tiêu đề để dải icon không phải rộng theo wing trái 150pt.
        return titleReveal && !launcherOpen ? .reading : .resting
    }

    // MARK: Geometry (wings around the fixed camera core)

    // Symmetric wings while playing; the reading state only grows the LEFT wing
    // (the 150pt title expansion), keeping the right wing steady.
    var leftReveal: CGFloat {
        if breakActive { return breakLeftWing }
        if claudeAlert != nil { return claudeAlertLeftWing }
        // Clawd (25pt) thay chỗ icon nguồn nhạc (18pt) → wing trái nhỉnh hơn một chút.
        let clawd = claudeIndicatorVisible
        switch compactState {
        case .quiet:   return clawd ? 54 : 10
        case .resting: return clawd ? 54 : 40
        case .reading: return clawd ? 166 : 150
        }
    }
    var rightReveal: CGFloat {
        if breakActive { return breakRightWing }
        if claudeAlert != nil { return claudeAlertRightWing }
        // Bấm soundwave → ◀ ⏯ ▶ ở wing phải, nới rộng cho vừa 3 nút.
        if hoverControls { return 106 }
        var base: CGFloat = compactState == .quiet ? 10 : 40
        // Đồng hồ đếm ngược chiếm chỗ waveform ở wing phải → nới rộng để badge đủ chỗ.
        if anyTimerRunning { base = max(base, 42) }
        return base
    }
    /// True khi người dùng đã bấm soundwave — morph waveform thành nút và nới wing phải.
    var hoverControls: Bool { transportVisible }

    /// Bấm soundwave → hiện ◀ ⏯ ▶ (chỉ bật, bấm lần nữa vào khe giữa nút không tắt).
    func showTransport() {
        guard hasMedia, !expanded, !showingHUD, !transportVisible else { return }
        // Đang điều khiển nhạc thì không bật quick tool (và đóng nếu đang mở).
        closeLauncher()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { transportVisible = true }
    }
    private func hideTransport() {
        guard transportVisible else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { transportVisible = false }
    }

    // MARK: Launcher (hover lâu → dải icon tính năng nhanh)

    /// Dải icon đang mở dưới notch.
    @Published private(set) var launcherOpen = false
    /// Tính năng đang mở trong launcher (nil = đang xem hàng icon).
    @Published var launcherFeature: LauncherFeature? {
        didSet { noteLauncherInteraction() }
    }
    private var launcherWork: DispatchWorkItem?
    private var launcherIdleWork: DispatchWorkItem?
    let launcherRevealDelay: TimeInterval = 0.75
    /// Chuột rời dải icon → đợi chừng này rồi mới thu (lỡ tay trượt ra vẫn kịp quay lại).
    let launcherLeaveGrace: TimeInterval = 0.8
    /// Đang trong một tính năng mà chuột rời notch → tự thu sau chừng này giây.
    let launcherIdleClose: TimeInterval = 20
    /// Hàng icon + một dòng tên tool đang hover bên dưới.
    let launcherStripHeight: CGFloat = 50

    private var canShowLauncher: Bool {
        !expanded && !showingHUD && !shelfActive && !systemFileDragActive && !breakActive
            && claudeAlert == nil && !transportVisible && !LauncherFeature.allCases.isEmpty
    }
    var launcherVisible: Bool { launcherOpen && !expanded && !showingHUD && !shelfActive }

    // MARK: Claude Code (tiến trình qua hook)

    @Published private(set) var claudeSessions: [ClaudeSession] = []
    /// Thông báo ngắn ở hai wing khi một phiên xong / chờ duyệt.
    @Published private(set) var claudeAlert: ClaudeTransition?
    private var claudeAlertWork: DispatchWorkItem?
    let claudeAlertLeftWing: CGFloat = 212
    let claudeAlertRightWing: CGFloat = 12
    /// Lượt làm ngắn hơn chừng này thì không bung "xong rồi" (tránh ồn).
    let claudeDoneMinDuration: TimeInterval = 10

    var claudeIndicatorVisible: Bool {
        AppSettings.shared.claudeOn && claudeSessions.contains(where: \.isActive)
    }
    var claudeWaiting: Bool { claudeSessions.contains { $0.state == .waiting } }
    /// Compact có gì để hiện ở wing không (nhạc hoặc Clawd).
    var hasCompactContent: Bool { hasMedia || claudeIndicatorVisible }

    private func handleClaude(_ t: ClaudeTransition) {
        let s = AppSettings.shared
        guard s.claudeOn else { return }
        let kind: ClaudeChime.Kind
        switch t {
        case .waiting: kind = .waiting
        case .done(let x, let d):
            kind = .done
            guard d >= claudeDoneMinDuration else { return }
            // Đang nhìn đúng app chứa phiên → không cần báo "xong".
            if let b = x.bundleID, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == b { return }
        }
        if s.claudeSoundOn { ClaudeChime.play(kind) }
        // Notch đang bận thì chỉ kêu, chỉ báo ở wing vẫn cập nhật.
        guard !expanded, !showingHUD, !shelfActive, !breakActive, !launcherOpen else { return }
        hideTransport()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { claudeAlert = t }
        claudeAlertWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissClaudeAlert() }
        claudeAlertWork = work
        let hold: TimeInterval = kind == .waiting ? 8 : 5
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
    }

    func dismissClaudeAlert() {
        claudeAlertWork?.cancel(); claudeAlertWork = nil
        guard claudeAlert != nil else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { claudeAlert = nil }
    }

    #if DEBUG
    /// Chỉ cho snapshot test: dựng trạng thái Claude mà không cần hook thật.
    func _previewClaude(sessions: [ClaudeSession], alert: ClaudeTransition? = nil) {
        claudeSessions = sessions
        claudeAlert = alert
    }
    #endif

    /// Bấm vào thông báo → mở app chứa phiên.
    func openClaudeAlert() {
        switch claudeAlert {
        case .waiting(let s)?, .done(let s, _)?: ClaudeActivityStore.focus(s)
        case nil: break
        }
        dismissClaudeAlert()
    }
    var launcherBodyHeight: CGFloat { launcherFeature?.bodyHeight ?? launcherStripHeight }
    /// Canh giữa notch: đủ rộng cho tính năng và cho hàng wing (bù lệch tâm hai wing).
    var launcherWidth: CGFloat {
        max(launcherFeature?.width ?? 240, compactWidth + abs(rightReveal - leftReveal))
    }

    private func scheduleLauncherReveal() {
        launcherWork?.cancel(); launcherWork = nil
        if hovering {
            launcherIdleWork?.cancel(); launcherIdleWork = nil
            guard !launcherOpen, canShowLauncher else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, hovering, canShowLauncher else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { self.launcherOpen = true }
            }
            launcherWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + launcherRevealDelay, execute: work)
        } else if launcherOpen {
            if launcherFeature == nil { scheduleLauncherLeaveClose() } else { noteLauncherInteraction() }
        }
    }

    /// Hẹn thu hàng icon sau `launcherLeaveGrace`; hover lại (scheduleLauncherReveal) sẽ huỷ.
    private func scheduleLauncherLeaveClose() {
        launcherIdleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !hovering, launcherFeature == nil else { return }
            closeLauncher()
        }
        launcherIdleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + launcherLeaveGrace, execute: work)
    }

    /// Có thao tác trong tính năng (gõ phím…) → hoãn đồng hồ tự thu.
    func noteLauncherInteraction() {
        launcherIdleWork?.cancel(); launcherIdleWork = nil
        guard launcherOpen, launcherFeature != nil, !hovering else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !hovering else { return }
            closeLauncher()
        }
        launcherIdleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + launcherIdleClose, execute: work)
    }

    func openLauncherFeature(_ f: LauncherFeature) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { launcherFeature = f }
    }
    /// ← trong tính năng: về hàng icon (hoặc thu hẳn nếu chuột đã rời notch).
    func launcherBack() {
        guard launcherFeature != nil else { closeLauncher(); return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { launcherFeature = nil }
        if !hovering { closeLauncher() }
    }
    func closeLauncher() {
        launcherWork?.cancel(); launcherWork = nil
        launcherIdleWork?.cancel(); launcherIdleWork = nil
        guard launcherOpen || launcherFeature != nil else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            launcherOpen = false
            launcherFeature = nil
        }
    }
    var compactHeight: CGFloat { compactState == .quiet ? 38 : 40 }
    var compactWidth: CGFloat { leftReveal + coreWidth + rightReveal }
    /// Fixed marquee viewport for the title (left reading wing minus icon + pads).
    var titleViewport: CGFloat { 150 - 18 - 13 - 8 }
    /// Phiên nên nhảy tới khi bấm Clawd: đang chờ duyệt trước, rồi đang chạy.
    var claudeFocusTarget: ClaudeSession? { claudeSessions.first(where: \.isActive) }

    // Expanded window. (Bề ngang gọn; chiều cao giữ nguyên.)
    let expandedWidth: CGFloat = 560
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
    let clipboardWidth: CGFloat = 640
    let clipboardHeight: CGFloat = 210
    /// Chiều cao canvas cố định lớn nhất — panel window phải đủ cao cho mọi state.
    var maxSurfaceHeight: CGFloat {
        max(expandedHeight, listExpandedHeight, calendarMaxHeight, filesExpandedHeight, shelfHeight)
    }
    /// Bề ngang canvas cố định lớn nhất — panel window phải đủ rộng cho mọi state.
    var maxSurfaceWidth: CGFloat {
        max(expandedWidth, hudWidth, filesExpandedWidth, shelfWidth)
    }

    var isListOpen: Bool { expanded && showList }

    /// Files đang mở rộng toàn chiều ngang (ẩn sidebar, làm việc chính với tab).
    var filesWide: Bool { expanded && filesTabActive && filesExpanded }

    /// KHÔNG thu notch khi bấm ra ngoài khi: Files wide (⤢) HOẶC người dùng bật ghim
    /// (📌). Còn lại (dạng nhỏ không ghim, tab khác) vẫn thu như cũ.
    var keepOpenOnOutsideClick: Bool { filesWide || (filesTabActive && pinnedOpen) }

    var surfaceWidth: CGFloat {
        if shelfActive { return shelfWidth }
        if showingHUD { return hudWidth }
        if launcherVisible { return launcherWidth }
        if expanded && learnPopup { return learnPopupWidth }
        if filesWide { return filesExpandedWidth }
        if expanded && clipTabActive { return clipboardWidth }
        return expanded ? expandedWidth : compactWidth
    }
    /// Tab Chuỗi tự tạo đang mở trình sửa → panel cao 300px cho thoải mái.
    @Published var timerEditorTall = false

    var surfaceHeight: CGFloat {
        if shelfActive { return shelfHeight }
        if showingHUD { return hudHeight }
        if launcherVisible { return compactHeight + launcherBodyHeight }
        if !expanded { return compactHeight }
        if learnPopup { return learnPopupHeight }
        if timerEditorTall { return 300 }
        if isListOpen { return listExpandedHeight }
        if clipTabActive { return clipboardHeight }
        if filesTabActive { return filesExpanded ? filesExpandedHeight : expandedHeight }
        if calTabActive { return calExpanded ? calendarExpandedHeight : expandedHeight }
        if notifTabActive { return expandedHeight }   // 150px như tab mặc định
        if panelWantsTall { return calendarExpandedHeight }
        return expandedHeight
    }
    /// Keep the camera core centred on the notch: shift by half the reveal imbalance.
    /// HUD and expanded are both centred, so no shift.
    var centerXOffset: CGFloat { isCentred ? 0 : wingImbalance }
    /// Lệch tâm do hai wing không đều — hàng wing trong launcher bù lại đúng chừng này.
    var wingImbalance: CGFloat { (rightReveal - leftReveal) / 2 }
    /// Bề mặt canh giữa notch (thay vì canh theo lõi camera + wing trái).
    var isCentred: Bool { expanded || showingHUD || shelfActive || launcherVisible }
    /// Phóng nhẹ khi hover (và giữ nguyên suốt lúc launcher mở) — neo ở mép trên.
    var hoverScale: CGFloat { !expanded && (hovering || launcherVisible) ? 1.03 : 1.0 }

    var bottomRadius: CGFloat {
        if shelfActive { return 26 }
        if showingHUD { return 22 }
        if launcherVisible { return launcherFeature == nil ? 20 : 22 }
        if pillMode && !expanded { return surfaceHeight / 2 }
        return expanded ? 26 : (compactState == .quiet ? 10 : 14)
    }
    /// Launcher giữ "tai" 9 như lúc thu gọn: tai to hơn sẽ lấn mép thân vào trong,
    /// làm icon ở wing trông như bị đẩy sát mép khi dải icon thả xuống.
    var topRadius: CGFloat { pillMode ? 0 : ((expanded || shelfActive) ? 12 : 9) }
    /// Màn hình không có notch vật lý → hiển thị dạng pill nổi (bo cả 4 góc, cách mép trên).
    @Published var pillMode = false
    /// Khoảng cách pill ↔ mép trên màn hình.
    let pillGap: CGFloat = 6
    /// Bo góc trên ở chế độ pill: thu gọn = capsule, mở = khớp góc dưới.
    var pillTopRadius: CGFloat {
        guard pillMode else { return 0 }
        return (expanded || shelfActive || showingHUD || launcherVisible) ? bottomRadius : surfaceHeight / 2
    }

    /// Đặt bởi global hotkey (⌃⌥1/2/3) — NotchRootView phân giải theo danh sách tab
    /// đang hiển thị rồi tự xoá về nil. 1-based.
    @Published var pendingTabIndex: Int?
    /// Yêu cầu nhảy tới một tab cụ thể (dùng cho auto-popup Learn).
    @Published var pendingTab: RailTab?

    // MARK: Learn auto-popup
    private var learnTick: Timer?
    /// Lưu bền (UserDefaults) — nếu chỉ giữ trong RAM, mỗi lần app khởi động lại
    /// đồng hồ bị reset và popup không bao giờ tới hạn.
    private var lastLearnPopup: Date {
        get { UserDefaults.standard.object(forKey: "learn.lastPopup") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "learn.lastPopup") }
    }
    private let launchedAt = Date()
    /// Không bung ngay lúc vừa mở app (kể cả khi đã quá hạn).
    private let learnLaunchGrace: TimeInterval = 60
    private var learnCollapseWork: DispatchWorkItem?
    /// Popup tự thu sau chừng này giây nếu người dùng chưa trả lời.
    private let learnPopupLinger: TimeInterval = 45

    func startLearnScheduler() {
        learnTick = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.learnTickFired() }
        }
    }

    private func learnTickFired() {
        let s = AppSettings.shared
        guard s.showLearn, s.learnAutoPopup, !s.learnPaused else { return }
        guard Date().timeIntervalSince(launchedAt) >= learnLaunchGrace,
              Date().timeIntervalSince(lastLearnPopup) >= Double(s.learnPopupMinutes) * 60 else { return }
        // Đang dùng notch / kệ / HUD → để lượt sau.
        guard !expanded, !shelfActive, !showingHUD, !hovering, !launcherOpen, !breakActive, claudeAlert == nil else { return }
        // App phía trước full màn hình (phim/game/họp) → không chen vào, thử lại lượt sau.
        if s.learnSkipFullscreen && FullscreenDetector.isFrontAppFullscreen() { return }
        popLearn()
    }

    /// Popup Learn gọn: notch bung ra đúng 1 thẻ (không rail tab), kèm âm báo.
    @Published var learnPopup = false
    let learnPopupWidth: CGFloat = 400
    let learnPopupHeight: CGFloat = 250

    /// Bung 1 lượt học từ bộ từ hôm nay; tự thu nếu không trả lời.
    func popLearn() {
        lastLearnPopup = Date()
        guard !expanded else { return }
        let prompt = learn.ensurePrompt()
        if prompt == nil && !learn.needsReviewSummary {
            // Bài hôm nay đã xong: chỉ bung 1 lần để báo hoàn thành + mời chọn tiếp.
            guard learn.dailyNeedsAnnounce else { return }
            learn.markDailyAnnounced()
        }
        learnPopup = true
        expanded = true; clearHUD()
        if AppSettings.shared.learnSoundEnabled { LearnChime.play(volume: Float(AppSettings.shared.learnSoundVolume)) }
        learnCollapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, expanded, learn.current == prompt else { return }
            collapse()
        }
        learnCollapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + learnPopupLinger, execute: work)
    }

    // MARK: Nhắc đứng dậy + uống nước (thụ động, theo `BreakSchedule`)

    /// Lời nhắc đang hiện ở hai wing (không bung panel).
    @Published private(set) var breakActive = false
    /// Mèo + chữ nằm hết ở wing trái (đồng bộ với Clawd); wing phải chỉ còn mép nhỏ.
    let breakLeftWing: CGFloat = 176
    let breakRightWing: CGFloat = 12
    let breakDuration: TimeInterval = 6
    private var breakTick: Timer?
    private var breakHideWork: DispatchWorkItem?
    /// Mốc gần nhất đã xử lý (đã nhắc hoặc đã bỏ) — lưu bền để khởi động lại app
    /// trong cùng khung 5' không nhắc lặp.
    private var lastBreakSlot: Date? {
        get { UserDefaults.standard.object(forKey: "break.lastSlot") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "break.lastSlot") }
    }

    func startBreakScheduler() {
        breakTick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.breakTickFired() }
        }
    }

    private func breakTickFired() {
        guard AppSettings.shared.breakReminderOn,
              let slot = BreakSchedule.dueSlot(now: Date(), lastHandled: lastBreakSlot) else { return }
        // Đã rời máy (khoá màn hình / không đụng phím chuột > 5') → coi như đã đứng dậy.
        if UserPresence.isAway(idleThreshold: 5 * 60) { lastBreakSlot = slot; return }
        // Notch đang bận (panel, popup Learn, HUD, kệ, launcher, kéo file) → chờ lượt
        // tick sau; quá cửa sổ 5' thì `dueSlot` tự bỏ mốc này.
        guard !expanded, !showingHUD, !shelfActive, !launcherOpen, !systemFileDragActive, claudeAlert == nil else { return }
        lastBreakSlot = slot
        showBreak()
    }

    /// Hiện lời nhắc ~6s kèm âm (trừ khi app phía trước đang full màn hình).
    func showBreak() {
        guard !breakActive else { return }
        hideTransport()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { breakActive = true }
        let s = AppSettings.shared
        if s.breakSoundOn, !FullscreenDetector.isFrontAppFullscreen() {
            BreakChime.play(volume: Float(s.breakVolume))
        }
        breakHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissBreak() }
        breakHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + breakDuration, execute: work)
    }

    func dismissBreak() {
        breakHideWork?.cancel(); breakHideWork = nil
        guard breakActive else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { breakActive = false }
    }

    // MARK: Actions
    func toggleExpanded() { expanded.toggle(); if expanded { clearHUD() } }
    func collapse() { expanded = false; showList = false; filesSelCount = 0; learnPopup = false }

    /// Xong lượt trong popup → ghi nhận và thu notch (lượt sau popup chọn từ kế).
    func finishLearnPopup() {
        learn.finishCurrent()
        learnCollapseWork?.cancel()
        collapse()
    }

    // MARK: Tự thu panel mở rộng (Lịch / Files)
    //
    /// Lịch (tháng) và Files (toàn chiều ngang) tự thu về dạng nhỏ sau
    /// `autoShrinkDelay` giây không tương tác. Con trỏ còn trên notch, hoặc notch
    /// đang đóng, đều tính là "còn dùng" ⇒ hẹn lại thay vì thu.
    let autoShrinkDelay: TimeInterval = 30

    /// Đặt lại đồng hồ tự thu. Gọi mỗi khi có tương tác đáng kể (hover, đổi tab,
    /// bấm trong panel) hoặc khi trạng thái mở rộng thay đổi.
    func noteInteraction() {
        autoShrinkWork?.cancel()
        autoShrinkWork = nil
        guard filesExpanded || calExpanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if hovering || !expanded { noteInteraction(); return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                self.filesExpanded = false
                self.calExpanded = false
            }
        }
        autoShrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoShrinkDelay, execute: work)
    }
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
        guard !expanded, !shelfActive, !launcherOpen else { return }
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

    /// Open a notification's click target: its embedded deep link when the
    /// sending app provided one (jumps straight to the conversation/section),
    /// otherwise just activate the app.
    func openNotification(_ record: NotificationRecord) {
        guard let link = record.deepLink else {
            openApp(bundleId: record.bundleId)
            return
        }
        // Route the link through the sending app when it can handle it, so a
        // plain https link doesn't bounce to the browser for an app that owns it.
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleId),
           let handler = NSWorkspace.shared.urlForApplication(toOpen: link), handler == appURL {
            NSWorkspace.shared.open([link], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(link)
        }
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
        if let record = hudNotification { openNotification(record) }
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
    /// Volume of the playing source itself (not the system volume).
    func setVolume(_ volume: Double, live: Bool = false) { media.setVolume(volume, live: live) }
    func start() {
        media.start(); media.refresh(); notifier.start()
        startLearnScheduler(); startBreakScheduler()
        let claude = ClaudeActivityStore.shared
        claude.$sessions.receive(on: RunLoop.main)
            .sink { [weak self] in self?.claudeSessions = $0 }.store(in: &bag)
        claude.transitions.receive(on: RunLoop.main)
            .sink { [weak self] in self?.handleClaude($0) }.store(in: &bag)
        claude.start()
    }
}
