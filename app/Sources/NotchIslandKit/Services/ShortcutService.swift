// File: Sources/NotchIsland/Services/ShortcutService.swift
import AppKit

/// Minimal global keyboard shortcut support using a global event monitor
/// (public API). This detects hotkeys system-wide but does not consume the
/// event — adequate for a toggle. Requires Accessibility permission to observe
/// keys while another app is frontmost.
final class ShortcutService {
    private var monitor: Any?
    /// keyCode + modifiers -> handler.
    private var bindings: [Binding] = []

    struct Binding {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let handler: () -> Void
    }

    /// Remove all bindings (e.g. before re-applying after a settings change).
    func clearBindings() { bindings.removeAll() }

    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        // Basic duplicate check.
        guard !bindings.contains(where: { $0.keyCode == keyCode && $0.modifiers == modifiers }) else {
            Log.shortcut.error("Duplicate shortcut ignored")
            return
        }
        bindings.append(Binding(keyCode: keyCode, modifiers: modifiers, handler: handler))
    }

    func start() {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        // Also observe local events so the shortcut works when our panel is key.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        for binding in bindings where binding.keyCode == event.keyCode && binding.modifiers == mods {
            binding.handler()
        }
    }

    deinit { stop() }
}
