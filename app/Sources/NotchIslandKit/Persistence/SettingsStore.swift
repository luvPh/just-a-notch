// File: Sources/NotchIsland/Persistence/SettingsStore.swift
import Foundation
import Combine

/// User-facing settings persisted in UserDefaults. Type-safe wrapper with
/// defaults and a schema version for future migrations.
final class SettingsStore: ObservableObject {
    static let schemaVersion = 1

    private let defaults: UserDefaults
    private enum Key {
        static let schemaVersion = "schemaVersion"
        static let simulateNotch = "simulateNotch"
        static let openOnHover = "openOnHover"
        static let hoverDelay = "hoverDelay"
        static let autoCollapseTimeout = "autoCollapseTimeout"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let cornerRadius = "cornerRadius"
        static let expandedWidth = "expandedWidth"
        static let compactHeight = "compactHeight"
        static let notchAlignmentOffset = "notchAlignmentOffset"
        static let reduceAnimation = "reduceAnimation"
        static let mediaEnabled = "mediaEnabled"
        static let systemStatusEnabled = "systemStatusEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let finderShelfEnabled = "finderShelfEnabled"
        static let toggleShortcut = "toggleShortcut"
        static let didCompleteOnboarding = "didCompleteOnboarding"
    }

    @Published var simulateNotch: Bool { didSet { defaults.set(simulateNotch, forKey: Key.simulateNotch) } }
    @Published var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Key.openOnHover) } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    @Published var autoCollapseTimeout: Double { didSet { defaults.set(autoCollapseTimeout, forKey: Key.autoCollapseTimeout) } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    @Published var cornerRadius: Double { didSet { defaults.set(cornerRadius, forKey: Key.cornerRadius) } }
    @Published var expandedWidth: Double { didSet { defaults.set(expandedWidth, forKey: Key.expandedWidth) } }
    @Published var compactHeight: Double { didSet { defaults.set(compactHeight, forKey: Key.compactHeight) } }
    @Published var notchAlignmentOffset: Double { didSet { defaults.set(notchAlignmentOffset, forKey: Key.notchAlignmentOffset) } }
    @Published var reduceAnimation: Bool { didSet { defaults.set(reduceAnimation, forKey: Key.reduceAnimation) } }
    @Published var mediaEnabled: Bool { didSet { defaults.set(mediaEnabled, forKey: Key.mediaEnabled) } }
    @Published var systemStatusEnabled: Bool { didSet { defaults.set(systemStatusEnabled, forKey: Key.systemStatusEnabled) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    @Published var finderShelfEnabled: Bool { didSet { defaults.set(finderShelfEnabled, forKey: Key.finderShelfEnabled) } }
    @Published var didCompleteOnboarding: Bool { didSet { defaults.set(didCompleteOnboarding, forKey: Key.didCompleteOnboarding) } }

    /// Custom global toggle shortcut. `nil` means use the built-in default.
    @Published var toggleShortcut: KeyboardShortcutDefinition? {
        didSet {
            if let toggleShortcut, let data = try? JSONEncoder().encode(toggleShortcut) {
                defaults.set(data, forKey: Key.toggleShortcut)
            } else {
                defaults.removeObject(forKey: Key.toggleShortcut)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateIfNeeded(defaults)

        simulateNotch = defaults.object(forKey: Key.simulateNotch) as? Bool ?? false
        openOnHover = defaults.object(forKey: Key.openOnHover) as? Bool ?? true
        hoverDelay = defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.25
        autoCollapseTimeout = defaults.object(forKey: Key.autoCollapseTimeout) as? Double ?? 4.0
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        cornerRadius = defaults.object(forKey: Key.cornerRadius) as? Double ?? 22
        expandedWidth = defaults.object(forKey: Key.expandedWidth) as? Double ?? 420
        compactHeight = defaults.object(forKey: Key.compactHeight) as? Double ?? 38
        notchAlignmentOffset = defaults.object(forKey: Key.notchAlignmentOffset) as? Double ?? 0
        reduceAnimation = defaults.object(forKey: Key.reduceAnimation) as? Bool ?? false
        mediaEnabled = defaults.object(forKey: Key.mediaEnabled) as? Bool ?? true
        systemStatusEnabled = defaults.object(forKey: Key.systemStatusEnabled) as? Bool ?? true
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? false
        finderShelfEnabled = defaults.object(forKey: Key.finderShelfEnabled) as? Bool ?? true
        didCompleteOnboarding = defaults.object(forKey: Key.didCompleteOnboarding) as? Bool ?? false
        if let data = defaults.data(forKey: Key.toggleShortcut) {
            toggleShortcut = try? JSONDecoder().decode(KeyboardShortcutDefinition.self, from: data)
        } else {
            toggleShortcut = nil
        }
    }

    /// Migrate persisted data across schema versions. Never crashes on bad data.
    static func migrateIfNeeded(_ defaults: UserDefaults) {
        let stored = defaults.integer(forKey: Key.schemaVersion) // 0 if unset
        guard stored < schemaVersion else { return }
        // v0 -> v1: nothing to transform yet; just stamp the version.
        defaults.set(schemaVersion, forKey: Key.schemaVersion)
        Log.persistence.info("Migrated settings schema \(stored) -> \(schemaVersion)")
    }

    func resetToDefaults() {
        simulateNotch = false
        openOnHover = true
        hoverDelay = 0.25
        autoCollapseTimeout = 4.0
        showMenuBarIcon = true
        cornerRadius = 22
        expandedWidth = 420
        compactHeight = 38
        notchAlignmentOffset = 0
        reduceAnimation = false
        mediaEnabled = true
        systemStatusEnabled = true
        notificationsEnabled = false
        finderShelfEnabled = true
        toggleShortcut = nil
        // Note: onboarding completion is intentionally NOT reset here.
    }
}
