// File: Sources/NotchIsland/Window/NotchGeometryProvider.swift
import AppKit

/// Describes the notch region and the anchor rect for the island on a screen.
struct NotchGeometry: Equatable {
    /// Full frame of the target screen (global coordinates).
    var screenFrame: CGRect
    /// Whether this screen has a physical (or simulated) notch.
    var hasNotch: Bool
    /// Width of the notch region in points.
    var notchWidth: CGFloat
    /// Height of the notch region (menu bar height) in points.
    var notchHeight: CGFloat
    /// The rect, in global (bottom-left origin) coordinates, where the compact
    /// island should be centred along the top edge.
    var topCenterAnchor: CGRect
}

/// Detects notch geometry using public AppKit API, with graceful fallbacks and
/// a user-controlled simulated-notch mode for Macs without a physical notch.
struct NotchGeometryProvider {
    /// Default assumed notch size when detection is not possible but simulation
    /// is requested. Not tied to any specific MacBook model.
    static let simulatedNotchWidth: CGFloat = 200
    static let fallbackMenuBarHeight: CGFloat = 24

    var simulateNotch: Bool
    var alignmentOffset: CGFloat
    var compactWidthHint: CGFloat

    init(simulateNotch: Bool, alignmentOffset: CGFloat = 0, compactWidthHint: CGFloat = 200) {
        self.simulateNotch = simulateNotch
        self.alignmentOffset = alignmentOffset
        self.compactWidthHint = compactWidthHint
    }

    /// Compute geometry for the given screen (defaults to `.main`).
    func geometry(for screen: NSScreen? = NSScreen.main) -> NotchGeometry? {
        guard let screen = screen ?? NSScreen.screens.first else { return nil }
        let frame = screen.frame

        let detectedNotchWidth = physicalNotchWidth(of: screen)
        let hasPhysicalNotch = detectedNotchWidth != nil
        let hasNotch = hasPhysicalNotch || simulateNotch

        let menuBarHeight = self.menuBarHeight(of: screen)
        let notchWidth = detectedNotchWidth ?? (simulateNotch ? Self.simulatedNotchWidth : compactWidthHint)

        return Self.compute(
            screenFrame: frame,
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            menuBarHeight: menuBarHeight,
            compactWidthHint: compactWidthHint,
            alignmentOffset: alignmentOffset
        )
    }

    /// Pure geometry computation — no `NSScreen` dependency, so it is unit
    /// testable. Anchors a top-centre rect flush under the menu bar.
    static func compute(screenFrame frame: CGRect,
                        hasNotch: Bool,
                        notchWidth: CGFloat,
                        menuBarHeight: CGFloat,
                        compactWidthHint: CGFloat,
                        alignmentOffset: CGFloat) -> NotchGeometry {
        let anchorWidth = hasNotch ? notchWidth : compactWidthHint
        let centerX = frame.midX + alignmentOffset - anchorWidth / 2
        // Global coords are bottom-left origin; the top edge is maxY.
        let anchorY = frame.maxY - menuBarHeight
        let anchor = CGRect(x: centerX, y: anchorY, width: anchorWidth, height: menuBarHeight)
        return NotchGeometry(
            screenFrame: frame,
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            notchHeight: menuBarHeight,
            topCenterAnchor: anchor
        )
    }

    /// Chooses the display that physically owns the notch. `NSScreen.main`
    /// follows the active app, so it can point to an external display.
    static func preferredScreenIndex(notchWidths: [CGFloat?], mainIndex: Int?) -> Int? {
        if let notchIndex = notchWidths.firstIndex(where: { $0 != nil }) {
            return notchIndex
        }
        if let mainIndex { return mainIndex }
        return notchWidths.indices.first
    }

    /// Width of the physical notch using `safeAreaInsets` (macOS 12+). Returns
    /// nil when the screen has no notch.
    func physicalNotchWidth(of screen: NSScreen) -> CGFloat? {
        if #available(macOS 12.0, *) {
            let insets = screen.safeAreaInsets
            // A non-zero top inset indicates a notch on built-in displays.
            guard insets.top > 0 else { return nil }
            // Derive the notch width from the auxiliary top areas if available.
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let width = screen.frame.width - left.width - right.width
                return max(0, width)
            }
            // Fallback: estimate from the safe-area top inset.
            return Self.simulatedNotchWidth
        }
        return nil
    }

    private func menuBarHeight(of screen: NSScreen) -> CGFloat {
        let full = screen.frame.height
        let visible = screen.visibleFrame.height
        // visibleFrame excludes the menu bar (and Dock). Use the top delta.
        let topDelta = (screen.frame.maxY - screen.visibleFrame.maxY)
        if topDelta > 1 { return topDelta }
        _ = full; _ = visible
        return Self.fallbackMenuBarHeight
    }
}
