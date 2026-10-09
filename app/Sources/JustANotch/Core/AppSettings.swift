import SwiftUI
import ServiceManagement

/// Một app được gán cho phím F. Lưu `bundleID` (bền khi app đổi chỗ/đổi tên)
/// kèm tên hiển thị để không phải tra lại Launch Services mỗi lần vẽ Settings.
struct FKeyApp: Codable, Equatable {
    var bundleID: String
    var name: String
}

/// App-wide, persisted user preferences. Single shared instance so both the
/// Settings panel (writer) and NotchRootView (reader: visible tabs, motion
/// override) observe the same source of truth. Backed by UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    // MARK: Tabs — which rail tabs are shown. Music + Settings are always on.
    @Published var showNotifications: Bool { didSet { d.set(showNotifications, forKey: "cfg.showNotifications") } }
    // MARK: Notifications — âm báo khi có thông báo mới (độc lập với chuông timer).
    @Published var notifSoundEnabled: Bool { didSet { d.set(notifSoundEnabled, forKey: "cfg.notifSoundOn") } }
    @Published var notifSoundName: String { didSet { d.set(notifSoundName, forKey: "cfg.notifSound") } }
    @Published var notifVolume: Double { didSet { d.set(notifVolume, forKey: "cfg.notifVolume") } }
    @Published var showCalendar: Bool { didSet { d.set(showCalendar, forKey: "cfg.showCalendar") } }
    @Published var showClipboard: Bool { didSet { d.set(showClipboard, forKey: "cfg.showClipboard") } }
    @Published var showTimer: Bool { didSet { d.set(showTimer, forKey: "cfg.showTimer") } }
    @Published var showLearn: Bool { didSet { d.set(showLearn, forKey: "cfg.showLearn") } }
    @Published var showTools: Bool { didSet { d.set(showTools, forKey: "cfg.showTools") } }
    /// Ánh nền + hiệu ứng của notch mở rộng đổi theo thời tiết (tính năng thêm, mặc định tắt).
    /// Giao diện notch mở rộng: "dark" (mặc định, như cũ) · "light" (kính sáng) · "system".
    @Published var appearanceMode: String { didSet { d.set(appearanceMode, forKey: "cfg.appearance") } }
    @Published var weatherAmbient: Bool { didSet { d.set(weatherAmbient, forKey: "cfg.weatherAmbient") } }
    // MARK: Learn — notch tự bung 1 lượt học sau mỗi N phút.
    @Published var learnAutoPopup: Bool { didSet { d.set(learnAutoPopup, forKey: "cfg.learnAutoPopup") } }
    @Published var learnPopupMinutes: Int { didSet { d.set(learnPopupMinutes, forKey: "cfg.learnPopupMinutes") } }
    @Published var learnSoundEnabled: Bool { didSet { d.set(learnSoundEnabled, forKey: "cfg.learnSound") } }
    @Published var learnSkipFullscreen: Bool { didSet { d.set(learnSkipFullscreen, forKey: "cfg.learnSkipFullscreen") } }
    @Published var learnSoundVolume: Double { didSet { d.set(learnSoundVolume, forKey: "cfg.learnSoundVolume") } }
    /// Tạm dừng popup Learn tới mốc này (nil = đang chạy; distantFuture = tới khi bật lại).
    @Published var learnPausedUntil: Date? { didSet { d.set(learnPausedUntil, forKey: "cfg.learnPausedUntil") } }

    var learnPaused: Bool { (learnPausedUntil ?? .distantPast) > Date() }

    /// Các lựa chọn tạm dừng (nhãn, mốc kết thúc).
    static func learnPauseOptions(now: Date = Date()) -> [(String, Date)] {
        let cal = Calendar.current
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        return [("30 phút", now.addingTimeInterval(30 * 60)),
                ("1 giờ", now.addingTimeInterval(3600)),
                ("2 giờ", now.addingTimeInterval(2 * 3600)),
                ("Hết hôm nay", endOfDay),
                ("Tới khi bật lại", .distantFuture)]
    }

    /// "Tạm dừng tới 15:30" / "Tạm dừng tới khi bật lại".
    var learnPauseLabel: String? {
        guard learnPaused, let u = learnPausedUntil else { return nil }
        if u == .distantFuture { return "Đã tạm dừng tới khi bật lại" }
        let f = DateFormatter(); f.dateFormat = Calendar.current.isDateInToday(u) ? "HH:mm" : "HH:mm dd/MM"
        return "Đã tạm dừng tới \(f.string(from: u))"
    }

    // MARK: Pomodoro — tuỳ biến chu kỳ + chuông.
    @Published var pomoWorkMinutes: Int { didSet { d.set(pomoWorkMinutes, forKey: "cfg.pomoWork") } }
    @Published var pomoShortMinutes: Int { didSet { d.set(pomoShortMinutes, forKey: "cfg.pomoShort") } }
    @Published var pomoLongMinutes: Int { didSet { d.set(pomoLongMinutes, forKey: "cfg.pomoLong") } }
    @Published var pomoRounds: Int { didSet { d.set(pomoRounds, forKey: "cfg.pomoRounds") } }
    @Published var pomoAutoStart: Bool { didSet { d.set(pomoAutoStart, forKey: "cfg.pomoAutoStart") } }
    @Published var timerSoundEnabled: Bool { didSet { d.set(timerSoundEnabled, forKey: "cfg.timerSoundOn") } }
    @Published var timerSoundName: String { didSet { d.set(timerSoundName, forKey: "cfg.timerSound") } }
    @Published var timerVolume: Double { didSet { d.set(timerVolume, forKey: "cfg.timerVolume") } }
    // Trang carousel đang xem trong tab Timer (0=Đơn, 1=Pomodoro, 2=Chuỗi tự tạo).
    @Published var timerPage: Int { didSet { d.set(timerPage, forKey: "cfg.timerPage") } }

    var pomodoroConfig: PomodoroConfig {
        PomodoroConfig(workMinutes: pomoWorkMinutes, shortBreakMinutes: pomoShortMinutes,
                       longBreakMinutes: pomoLongMinutes, roundsBeforeLongBreak: pomoRounds)
    }

    // MARK: Nhắc đứng dậy + uống nước (lịch cố định giờ làm, xem BreakSchedule).
    @Published var breakReminderOn: Bool { didSet { d.set(breakReminderOn, forKey: "cfg.breakOn") } }
    @Published var breakSoundOn: Bool { didSet { d.set(breakSoundOn, forKey: "cfg.breakSound") } }
    @Published var breakVolume: Double { didSet { d.set(breakVolume, forKey: "cfg.breakVolume") } }

    // MARK: Claude Code — chỉ báo tiến trình + thông báo xong/chờ duyệt (dữ liệu từ hook).
    @Published var claudeOn: Bool { didSet { d.set(claudeOn, forKey: "cfg.claudeOn") } }
    @Published var claudeSoundOn: Bool { didSet { d.set(claudeSoundOn, forKey: "cfg.claudeSound") } }

    // MARK: Motion — force reduced motion regardless of the system setting.
    @Published var forceReduceMotion: Bool { didSet { d.set(forceReduceMotion, forKey: "cfg.forceReduceMotion") } }

    // MARK: Màn hình — "" = tự động (ưu tiên màn có notch), ngược lại là tên màn hình.
    /// Clawd ngồi chill ở giữa pill (màn không có notch).
    // MARK: Chụp màn hình
    /// Thư mục lưu ảnh khi bấm "Lưu" (mặc định Desktop).
    @Published var shotFolder: String { didSet { d.set(shotFolder, forKey: "cfg.shotFolder") } }
    /// Chụp xong tự sao chép vào clipboard hệ thống.
    @Published var shotAutoCopy: Bool { didSet { d.set(shotAutoCopy, forKey: "cfg.shotAutoCopy") } }
    /// Chụp xong tự lưu vào thư mục.
    @Published var shotAutoSave: Bool { didSet { d.set(shotAutoSave, forKey: "cfg.shotAutoSave") } }
    /// Quay màn hình kèm âm thanh hệ thống.
    @Published var recordAudio: Bool { didSet { d.set(recordAudio, forKey: "cfg.recordAudio") } }
    /// Giữ bóng đổ khi chụp cửa sổ.
    @Published var shotWindowShadow: Bool { didSet { d.set(shotWindowShadow, forKey: "cfg.shotWindowShadow") } }

    @Published var pillMascot: Bool { didSet { d.set(pillMascot, forKey: "cfg.pillMascot") } }
    @Published var displayName: String { didSet { d.set(displayName, forKey: "cfg.displayName") } }

    // MARK: Hotkey — nhấn nhanh ⌘ hai lần để bung/đóng notch (cần quyền Accessibility).
    @Published var doubleTapCommand: Bool { didSet { d.set(doubleTapCommand, forKey: "cfg.doubleTapCommand") } }
    /// F1…F6 (bàn phím Apple: fn+F1…) đưa app đã gán ra trước, ở mọi nơi.
    /// Bật ⇒ app giữ 6 phím này toàn hệ thống nên chức năng gốc của chúng
    /// (độ sáng, Mission Control…) không còn hoạt động.
    @Published var fKeyAppsEnabled: Bool { didSet { d.set(fKeyAppsEnabled, forKey: "cfg.fKeyAppsOn") } }

    /// App gán cho F1…F6 (đúng `fKeyCount` ô, nil = chưa gán).
    @Published var fKeyApps: [FKeyApp?] { didSet { saveFKeyApps() } }

    /// Số phím F được bind. Dừng ở F6, phần còn lại của dãy F để cho hệ thống.
    static let fKeyCount = 6

    private func saveFKeyApps() {
        let payload = fKeyApps.map { $0 ?? FKeyApp(bundleID: "", name: "") }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        d.set(data, forKey: "cfg.fKeyApps")
    }

    private static func loadFKeyApps(_ d: UserDefaults) -> [FKeyApp?] {
        var slots = [FKeyApp?](repeating: nil, count: fKeyCount)
        guard let data = d.data(forKey: "cfg.fKeyApps"),
              let decoded = try? JSONDecoder().decode([FKeyApp].self, from: data) else { return slots }
        for (i, item) in decoded.enumerated() where i < fKeyCount {
            slots[i] = item.bundleID.isEmpty ? nil : item
        }
        return slots
    }

    // MARK: General — start at login (mirrors SMAppService state).
    @Published var launchAtLogin: Bool = false

    private init() {
        // Default the tab toggles to ON the first time (register defaults so a
        // brand-new install shows everything).
        d.register(defaults: [
            "cfg.showNotifications": true,
            "cfg.showCalendar": true,
            "cfg.showClipboard": true,
            "cfg.showTimer": true,
            "cfg.showLearn": true,
            "cfg.showTools": true,
            "cfg.learnAutoPopup": true,
            "cfg.learnPopupMinutes": 15,
            "cfg.learnSound": true,
            "cfg.learnSkipFullscreen": true,
            "cfg.learnSoundVolume": 0.6,
            "cfg.forceReduceMotion": false,
            "cfg.doubleTapCommand": false,
            "cfg.pillMascot": true,
            "cfg.shotAutoCopy": true, "cfg.shotAutoSave": false, "cfg.shotWindowShadow": true,
            "cfg.fKeyAppsOn": true,
            "cfg.pomoWork": 25, "cfg.pomoShort": 5, "cfg.pomoLong": 15,
            "cfg.pomoRounds": 4, "cfg.pomoAutoStart": true,
            "cfg.timerSoundOn": true, "cfg.timerSound": "Glass", "cfg.timerVolume": 0.8,
            "cfg.claudeOn": true, "cfg.claudeSound": true,
            "cfg.breakOn": true, "cfg.breakSound": true, "cfg.breakVolume": 0.6,
            "cfg.notifSoundOn": true, "cfg.notifSound": "Ping", "cfg.notifVolume": 0.7,
        ])
        showNotifications = d.bool(forKey: "cfg.showNotifications")
        notifSoundEnabled = d.bool(forKey: "cfg.notifSoundOn")
        notifSoundName = d.string(forKey: "cfg.notifSound") ?? "Ping"
        notifVolume = d.double(forKey: "cfg.notifVolume")
        showCalendar = d.bool(forKey: "cfg.showCalendar")
        showClipboard = d.bool(forKey: "cfg.showClipboard")
        showTimer = d.bool(forKey: "cfg.showTimer")
        showLearn = d.bool(forKey: "cfg.showLearn")
        showTools = d.bool(forKey: "cfg.showTools")
        weatherAmbient = d.bool(forKey: "cfg.weatherAmbient")
        appearanceMode = d.string(forKey: "cfg.appearance") ?? "dark"
        learnAutoPopup = d.bool(forKey: "cfg.learnAutoPopup")
        learnPopupMinutes = d.integer(forKey: "cfg.learnPopupMinutes")
        learnSoundEnabled = d.bool(forKey: "cfg.learnSound")
        learnSkipFullscreen = d.bool(forKey: "cfg.learnSkipFullscreen")
        learnSoundVolume = d.double(forKey: "cfg.learnSoundVolume")
        learnPausedUntil = d.object(forKey: "cfg.learnPausedUntil") as? Date
        pomoWorkMinutes = d.integer(forKey: "cfg.pomoWork")
        pomoShortMinutes = d.integer(forKey: "cfg.pomoShort")
        pomoLongMinutes = d.integer(forKey: "cfg.pomoLong")
        pomoRounds = d.integer(forKey: "cfg.pomoRounds")
        pomoAutoStart = d.bool(forKey: "cfg.pomoAutoStart")
        timerSoundEnabled = d.bool(forKey: "cfg.timerSoundOn")
        timerSoundName = d.string(forKey: "cfg.timerSound") ?? "Glass"
        timerVolume = d.double(forKey: "cfg.timerVolume")
        // Pomodoro + Chuỗi đã gộp thành "Nhịp": 4 trang cũ → 3 trang (đổi một lần).
        let oldPage = d.integer(forKey: "cfg.timerPage")
        let newPage = d.bool(forKey: "cfg.timerPageV2") ? oldPage : [0, 1, 1, 2][min(3, max(0, oldPage))]
        timerPage = newPage
        d.set(newPage, forKey: "cfg.timerPage"); d.set(true, forKey: "cfg.timerPageV2")
        claudeOn = d.bool(forKey: "cfg.claudeOn")
        claudeSoundOn = d.bool(forKey: "cfg.claudeSound")
        breakReminderOn = d.bool(forKey: "cfg.breakOn")
        breakSoundOn = d.bool(forKey: "cfg.breakSound")
        breakVolume = d.double(forKey: "cfg.breakVolume")
        forceReduceMotion = d.bool(forKey: "cfg.forceReduceMotion")
        doubleTapCommand = d.bool(forKey: "cfg.doubleTapCommand")
        displayName = d.string(forKey: "cfg.displayName") ?? ""
        pillMascot = d.bool(forKey: "cfg.pillMascot")
        shotFolder = d.string(forKey: "cfg.shotFolder")
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].path
        shotAutoCopy = d.bool(forKey: "cfg.shotAutoCopy")
        shotAutoSave = d.bool(forKey: "cfg.shotAutoSave")
        shotWindowShadow = d.bool(forKey: "cfg.shotWindowShadow")
        recordAudio = d.bool(forKey: "cfg.recordAudio")
        fKeyAppsEnabled = d.bool(forKey: "cfg.fKeyAppsOn")
        fKeyApps = Self.loadFKeyApps(d)
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    /// Register/unregister the login item, then reflect the real status back.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("[JustANotch] launchAtLogin toggle failed: \(error)")
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }
}
