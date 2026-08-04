// File: Sources/NotchIsland/App/SettingsView.swift
import SwiftUI

/// Native macOS settings with tabbed sections. Reads the shared environment's
/// settings store; changes persist immediately and propagate to the panel.
struct SettingsRootView: View {
    var body: some View {
        if let env = AppEnvironment.shared {
            SettingsTabs(settings: env.settings, env: env)
                .frame(width: 460, height: 380)
        } else {
            Text("Notch Island is still starting…").padding(40)
        }
    }
}

private struct SettingsTabs: View {
    @ObservedObject var settings: SettingsStore
    let env: AppEnvironment

    var body: some View {
        TabView {
            GeneralTab(settings: settings, env: env).tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab(settings: settings).tabItem { Label("Appearance", systemImage: "paintbrush") }
            FeaturesTab(settings: settings, env: env).tabItem { Label("Features", systemImage: "square.grid.2x2") }
            ShortcutsTab(settings: settings).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PermissionsTab(env: env).tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutTab(settings: settings).tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding()
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    let env: AppEnvironment
    @State private var launchAtLogin = false
    var body: some View {
        Form {
            if env.launchAtLogin.isSupported {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { env.launchAtLogin.setEnabled($0) }
                    .onAppear { launchAtLogin = env.launchAtLogin.currentState() == .enabled }
            }
            Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
            Toggle("Open on hover", isOn: $settings.openOnHover)
            HStack { Text("Hover delay"); Slider(value: $settings.hoverDelay, in: 0...1); Text(String(format: "%.2fs", settings.hoverDelay)) }
            HStack { Text("Auto-collapse"); Slider(value: $settings.autoCollapseTimeout, in: 0...10); Text(String(format: "%.0fs", settings.autoCollapseTimeout)) }
            Toggle("Reduce animation", isOn: $settings.reduceAnimation)
        }
    }
}

private struct AppearanceTab: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        Form {
            HStack { Text("Expanded width"); Slider(value: $settings.expandedWidth, in: 320...520); Text("\(Int(settings.expandedWidth))") }
            HStack { Text("Compact height"); Slider(value: $settings.compactHeight, in: 24...48); Text("\(Int(settings.compactHeight))") }
            HStack { Text("Corner radius"); Slider(value: $settings.cornerRadius, in: 8...40); Text("\(Int(settings.cornerRadius))") }
            HStack { Text("Notch offset"); Slider(value: $settings.notchAlignmentOffset, in: -100...100); Text("\(Int(settings.notchAlignmentOffset))") }
            Toggle("Simulate notch on this display", isOn: $settings.simulateNotch)
        }
    }
}

private struct FeaturesTab: View {
    @ObservedObject var settings: SettingsStore
    let env: AppEnvironment
    var body: some View {
        Form {
            Toggle("Media", isOn: $settings.mediaEnabled)
            Toggle("System status", isOn: $settings.systemStatusEnabled)
            Toggle("Finder Shelf", isOn: $settings.finderShelfEnabled)
            Divider()
            Toggle("App notifications", isOn: $settings.notificationsEnabled)
                .onChange(of: settings.notificationsEnabled) { enabled in
                    if enabled { env.notificationService.requestAuthorization { _ in } }
                }
            Text("Notifications request permission only when enabled.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        Form {
            HStack {
                Text("Show/Hide Island")
                Spacer()
                ShortcutRecorder(shortcut: $settings.toggleShortcut, defaultDisplay: "⌥⌘Space")
            }
            Text("Global shortcuts require Accessibility permission to work while another app is active.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PermissionsTab: View {
    let env: AppEnvironment
    @State private var notifState: PermissionState = .unknown
    var body: some View {
        Form {
            permissionRow(name: "Notifications", state: notifState,
                          detail: "For the app's own alerts (low battery, etc.).")
            permissionRow(name: "Accessibility", state: .unknown,
                          detail: "For the global toggle shortcut. Grant in System Settings › Privacy.")
            permissionRow(name: "Automation", state: .unknown,
                          detail: "For controlling Music / Spotify / YouTube. Prompted on first use.")
            Button("Open Privacy & Security settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .onAppear { env.notificationService.authorizationState { s in DispatchQueue.main.async { notifState = s } } }
    }

    private func permissionRow(name: String, state: PermissionState, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(label(state)).font(.caption).foregroundStyle(color(state))
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func label(_ s: PermissionState) -> String {
        switch s {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .unsupported: return "Unsupported"
        case .unknown: return "Check in System Settings"
        }
    }
    private func color(_ s: PermissionState) -> Color {
        switch s {
        case .granted: return .green
        case .denied, .restricted: return .orange
        default: return .secondary
        }
    }
}

private struct AboutTab: View {
    @ObservedObject var settings: SettingsStore
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 40))
            Text("Notch Island").font(.title2).bold()
            Text("Version \(version)").foregroundStyle(.secondary)
            Button("Reset settings to defaults") { settings.resetToDefaults() }
            Spacer()
        }
        .frame(maxWidth: .infinity).padding()
    }
}
