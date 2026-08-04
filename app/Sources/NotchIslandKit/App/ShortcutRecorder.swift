// File: Sources/NotchIslandKit/App/ShortcutRecorder.swift
import SwiftUI
import AppKit

/// A button that records a single global keyboard shortcut. While recording it
/// captures the next key-down (with modifiers) via a local event monitor.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyboardShortcutDefinition?
    let defaultDisplay: String

    @State private var recording = false
    @State private var monitor: Any?
    @State private var errorText: String?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(recording ? "Press keys…" : (shortcut?.displayString ?? defaultDisplay))
                    .frame(minWidth: 120)
                    .padding(.vertical, 4)
            }
            .accessibilityLabel("Record shortcut")
            if shortcut != nil {
                Button("Reset") { shortcut = nil; stop() }
                    .accessibilityLabel("Reset to default shortcut")
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        errorText = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let def = KeyboardShortcutDefinition(
                keyCode: event.keyCode,
                modifierFlagsRaw: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            )
            if def.isValidGlobalShortcut {
                shortcut = def
                stop()
            } else {
                errorText = "Include ⌘, ⌥ or ⌃"
            }
            return nil // swallow the event while recording
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
