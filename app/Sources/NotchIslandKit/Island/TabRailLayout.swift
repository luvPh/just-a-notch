// File: Sources/NotchIslandKit/Island/TabRailLayout.swift
import Foundation

/// Pure layout for the three-tab rail: the active tab is a labelled capsule,
/// inactive tabs are icon-only capsules. Derives widths and label visibility
/// from available width and Reduce Motion; the view maps the active tab onto
/// `activeWidth` and the other two onto `inactiveWidth`.
struct TabRailLayout: Equatable {
    let activeWidth: CGFloat
    let inactiveWidth: CGFloat
    let gap: CGFloat
    let showsActiveLabel: Bool
    let animates: Bool

    var totalWidth: CGFloat { activeWidth + inactiveWidth * 2 + gap * 2 }
}

enum TabRailLayoutModel {
    static let activeWidth: CGFloat = 152
    static let minActiveWidth: CGFloat = 116
    static let inactiveWidth: CGFloat = 58
    static let gap: CGFloat = 8

    static func layout(availableWidth: CGFloat, reduceMotion: Bool) -> TabRailLayout {
        // The fixed cost of the two inactive capsules plus the two gaps.
        let fixed = inactiveWidth * 2 + gap * 2
        let active = max(minActiveWidth, min(activeWidth, availableWidth - fixed))
        return TabRailLayout(
            activeWidth: active,
            inactiveWidth: inactiveWidth,
            gap: gap,
            showsActiveLabel: active >= minActiveWidth,
            animates: !reduceMotion)
    }
}
