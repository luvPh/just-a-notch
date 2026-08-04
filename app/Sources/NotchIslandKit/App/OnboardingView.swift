// File: Sources/NotchIslandKit/App/OnboardingView.swift
import SwiftUI

/// A short 3-step first-run wizard (trimmed from the original 7-step spec):
/// 1) welcome + notch mode, 2) pick features, 3) shortcut + finish.
/// Permissions are requested lazily later, not here.
struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    let env: AppEnvironment
    let onFinish: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 20) {
            content
            Spacer()
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                Button(step < 2 ? "Next" : "Finish") {
                    if step < 2 { step += 1 } else { finish() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460, height: 360)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            step0
        case 1:
            step1
        default:
            step2
        }
    }

    private var step0: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 44))
            Text("Welcome to Notch Island").font(.title2).bold()
            Text("An interactive overlay that lives in your notch. If your Mac has no notch, turn on simulated mode.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Toggle("Simulate a notch on this display", isOn: $settings.simulateNotch)
                .padding(.top, 8)
        }
    }

    private var step1: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose features").font(.title3).bold()
            Text("You can change these any time in Settings.").font(.caption).foregroundStyle(.secondary)
            Toggle("Media controls", isOn: $settings.mediaEnabled)
            Toggle("System status", isOn: $settings.systemStatusEnabled)
            Toggle("Finder Shelf", isOn: $settings.finderShelfEnabled)
            Toggle("App notifications", isOn: $settings.notificationsEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var step2: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard").font(.system(size: 40))
            Text("You're all set").font(.title3).bold()
            HStack {
                Text("Toggle the island with")
                ShortcutRecorder(shortcut: $settings.toggleShortcut, defaultDisplay: "⌥⌘Space")
            }
            Text("Some features ask for permission the first time you use them.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func finish() {
        settings.didCompleteOnboarding = true
        if settings.notificationsEnabled {
            env.notificationService.requestAuthorization { _ in }
        }
        onFinish()
    }
}
