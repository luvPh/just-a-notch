import Foundation

/// The one-pass marquee plan derived synchronously from a measured title.
struct CompactTitleMarqueePlan {
    let overflow: CGFloat
    let panDuration: TimeInterval

    init(textWidth: CGFloat, viewport: CGFloat, pointsPerSecond: CGFloat = 34) {
        overflow = max(0, textWidth - viewport)
        panDuration = TimeInterval(overflow / pointsPerSecond)
    }
}

/// Coordinates a one-pass marquee and the hold at the title's trailing edge
/// before the compact wing retracts.
struct TitleRevealTiming {
    let trailingHold: TimeInterval
    let retractionDelay: TimeInterval

    init(pan: TimeInterval) {
        trailingHold = max(1, 3 - pan)
        retractionDelay = pan + trailingHold
    }
}
