// File: Sources/NotchIsland/App/AppEnvironment.swift
import Foundation
import Combine
import AppKit

/// Dependency-injection container. Constructed once at launch; owns the
/// services and vends the SwiftUI panel view models. UI never instantiates
/// services directly.
@MainActor
final class AppEnvironment {
    /// Set by the AppDelegate so the SwiftUI `Settings` scene can reach services.
    static private(set) var shared: AppEnvironment?

    let notificationService = NotificationService()
    let launchAtLogin = LaunchAtLoginService()
    private var cancellables: Set<AnyCancellable> = []
    private var lowBatteryFired = false
    let settings: SettingsStore
    let islandViewModel: IslandViewModel

    // Services (protocol-typed so they can be mocked).
    let finderService: FinderServiceProtocol
    let systemMonitor: SystemMonitorServiceProtocol
    let mediaService: MediaServiceProtocol
    let shortcutService: ShortcutService
    var toggleOverlayHandler: (() -> Void)?

    // Panel view models.
    let mediaPanelVM: MediaPanelViewModel
    let systemPanelVM: SystemPanelViewModel
    let finderPanelVM: FinderPanelViewModel

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        let islandVM = IslandViewModel(settings: settings)
        self.islandViewModel = islandVM

        let finder = FinderService()
        let sysmon = SystemMonitorService()
        let media = MediaService()
        let shortcuts = ShortcutService()

        self.finderService = finder
        self.systemMonitor = sysmon
        self.mediaService = media
        self.shortcutService = shortcuts

        self.mediaPanelVM = MediaPanelViewModel(service: media)
        self.systemPanelVM = SystemPanelViewModel(service: sysmon)
        self.finderPanelVM = FinderPanelViewModel(service: finder)
        if settings.mediaEnabled { media.start(); media.refresh() }
        AppEnvironment.shared = self
        observeSystemForEvents()
    }

    /// Surface a low-battery internal event (Level 1) the first time battery
    /// drops below 15% while not charging; reset once charging/recovered.
    private func observeSystemForEvents() {
        systemMonitor.snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                guard let self, let pct = snap.batteryPercentage else { return }
                if pct < 0.15 && !snap.isCharging {
                    if !self.lowBatteryFired {
                        self.lowBatteryFired = true
                        self.islandViewModel.post(IslandEvent(
                            type: .systemAlert, priority: .high, duration: 4.0,
                            payload: IslandEventPayload(title: "Low battery",
                                                        subtitle: "\(Int(pct * 100))%",
                                                        symbolName: "battery.25",
                                                        content: .systemStatus)))
                        if self.settings.notificationsEnabled {
                            self.notificationService.post(title: "Low battery",
                                                          body: "Battery at \(Int(pct * 100))%.")
                        }
                    }
                } else if pct > 0.25 || snap.isCharging {
                    self.lowBatteryFired = false
                }
            }
            .store(in: &cancellables)
        // Keep a low-frequency monitor running so battery alerts work even when
        // the island is idle.
        systemMonitor.setActive(false)
        systemMonitor.start()
    }

    /// Default global toggle shortcut when the user hasn't set a custom one.
    static let defaultToggleShortcut = KeyboardShortcutDefinition(
        keyCode: 49, // kVK_Space
        modifierFlagsRaw: NSEvent.ModifierFlags([.command, .option]).rawValue
    )

    var effectiveToggleShortcut: KeyboardShortcutDefinition {
        settings.toggleShortcut ?? Self.defaultToggleShortcut
    }

    func toggleIsland() {
        if let toggleOverlayHandler {
            toggleOverlayHandler()
            return
        }
        if islandViewModel.state.isExpandedLike {
            islandViewModel.dismiss()
        } else {
            islandViewModel.clicked(IslandDefaultContent.select(
                mediaAvailable: settings.mediaEnabled && mediaService.hasAvailableSource
            ))
        }
    }

    /// Register (or re-register) global shortcuts from current settings.
    func registerDefaultShortcuts() {
        applyToggleShortcut()
        shortcutService.start()
        // Re-apply whenever the user changes the toggle shortcut.
        settings.$toggleShortcut
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyToggleShortcut() }
            .store(in: &cancellables)
    }

    private func applyToggleShortcut() {
        shortcutService.clearBindings()
        let sc = effectiveToggleShortcut
        shortcutService.register(keyCode: sc.keyCode, modifiers: sc.modifierFlags) { [weak self] in
            self?.toggleIsland()
        }
    }
}
