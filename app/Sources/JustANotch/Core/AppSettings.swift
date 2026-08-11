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
    @Published var showCalendar: Bool { didSet { d.set(showCalendar, forKey: "cfg.showCalendar") } }
    @Published var showClipboard: Bool { didSet { d.set(showClipboard, forKey: "cfg.showClipboard") } }
    @Published var showTimer: Bool { didSet { d.set(showTimer, forKey: "cfg.showTimer") } }

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
        ])
        showFiles = d.bool(forKey: "cfg.showFiles")
        showNotifications = d.bool(forKey: "cfg.showNotifications")
        showCalendar = d.bool(forKey: "cfg.showCalendar")
        showClipboard = d.bool(forKey: "cfg.showClipboard")
        showTimer = d.bool(forKey: "cfg.showTimer")
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
