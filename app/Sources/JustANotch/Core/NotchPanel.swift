// File: Sources/NotchIsland/Window/NotchPanel.swift
import AppKit

/// A borderless, transparent, non-activating floating panel that hosts the
/// island. It can appear on all Spaces and above (most) fullscreen apps.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Compact state must not steal keyboard focus.
        acceptsMouseMovedEvents = true
    }

    // Allow the panel to become key only when it actively needs input
    // (search, settings, shortcut capture). Controlled by the controller.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
