import SwiftUI
import ServiceManagement

/// App-wide, persisted user preferences. Single shared instance so both the
/// Settings panel (writer) and NotchRootView (reader: visible tabs, motion
/// override) observe the same source of truth. Backed by UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    // MARK: Tabs — which rail tabs are shown. Music + Settings are always on.
    @Published var showFiles: Bool { didSet { d.set(showFiles, forKey: "cfg.showFiles") } }
    @Published var showNotifications: Bool { didSet { d.set(showNotifications, forKey: "cfg.showNotifications") } }
    // MARK: Notifications — âm báo khi có thông báo mới (độc lập với chuông timer).
    @Published var notifSoundEnabled: Bool { didSet { d.set(notifSoundEnabled, forKey: "cfg.notifSoundOn") } }
    @Published var notifSoundName: String { didSet { d.set(notifSoundName, forKey: "cfg.notifSound") } }
    @Published var notifVolume: Double { didSet { d.set(notifVolume, forKey: "cfg.notifVolume") } }
    @Published var showCalendar: Bool { didSet { d.set(showCalendar, forKey: "cfg.showCalendar") } }
    @Published var showClipboard: Bool { didSet { d.set(showClipboard, forKey: "cfg.showClipboard") } }
    @Published var showTimer: Bool { didSet { d.set(showTimer, forKey: "cfg.showTimer") } }

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

    // MARK: Motion — force reduced motion regardless of the system setting.
    @Published var forceReduceMotion: Bool { didSet { d.set(forceReduceMotion, forKey: "cfg.forceReduceMotion") } }

    // MARK: Hotkey — nhấn nhanh ⌘ hai lần để bung/đóng notch (cần quyền Accessibility).
    @Published var doubleTapCommand: Bool { didSet { d.set(doubleTapCommand, forKey: "cfg.doubleTapCommand") } }

    // MARK: General — start at login (mirrors SMAppService state).
    @Published var launchAtLogin: Bool = false

    private init() {
        // Default the tab toggles to ON the first time (register defaults so a
        // brand-new install shows everything).
        d.register(defaults: [
            "cfg.showFiles": true,
            "cfg.showNotifications": true,
            "cfg.showCalendar": true,
            "cfg.showClipboard": true,
            "cfg.showTimer": true,
            "cfg.forceReduceMotion": false,
            "cfg.doubleTapCommand": false,
            "cfg.pomoWork": 25, "cfg.pomoShort": 5, "cfg.pomoLong": 15,
            "cfg.pomoRounds": 4, "cfg.pomoAutoStart": true,
            "cfg.timerSoundOn": true, "cfg.timerSound": "Glass", "cfg.timerVolume": 0.8,
            "cfg.notifSoundOn": true, "cfg.notifSound": "Ping", "cfg.notifVolume": 0.7,
        ])
        showFiles = d.bool(forKey: "cfg.showFiles")
        showNotifications = d.bool(forKey: "cfg.showNotifications")
        notifSoundEnabled = d.bool(forKey: "cfg.notifSoundOn")
        notifSoundName = d.string(forKey: "cfg.notifSound") ?? "Ping"
        notifVolume = d.double(forKey: "cfg.notifVolume")
        showCalendar = d.bool(forKey: "cfg.showCalendar")
        showClipboard = d.bool(forKey: "cfg.showClipboard")
        showTimer = d.bool(forKey: "cfg.showTimer")
        pomoWorkMinutes = d.integer(forKey: "cfg.pomoWork")
        pomoShortMinutes = d.integer(forKey: "cfg.pomoShort")
        pomoLongMinutes = d.integer(forKey: "cfg.pomoLong")
        pomoRounds = d.integer(forKey: "cfg.pomoRounds")
        pomoAutoStart = d.bool(forKey: "cfg.pomoAutoStart")
        timerSoundEnabled = d.bool(forKey: "cfg.timerSoundOn")
        timerSoundName = d.string(forKey: "cfg.timerSound") ?? "Glass"
        timerVolume = d.double(forKey: "cfg.timerVolume")
        timerPage = d.integer(forKey: "cfg.timerPage")
        forceReduceMotion = d.bool(forKey: "cfg.forceReduceMotion")
        doubleTapCommand = d.bool(forKey: "cfg.doubleTapCommand")
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
