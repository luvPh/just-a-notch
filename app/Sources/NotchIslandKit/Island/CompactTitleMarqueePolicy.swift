// File: Sources/NotchIslandKit/Island/CompactTitleMarqueePolicy.swift
import Foundation

/// Pure, deterministic decision for how a compact track title is presented in
/// the reading reveal: still (fits), a single delayed one-pass scroll
/// (overflows), or a static truncated line (Reduce Motion). Timing is derived
/// from measured text width, never character count.
enum CompactTitleMarqueePolicy {
    enum Decision: Equatable {
        /// Title fits the viewport; hold still for `hold` seconds.
        case fits(hold: TimeInterval)
        /// Title overflows; after `delay`, scroll `distance` pt over `duration`
        /// seconds, then hold `hold` seconds.
        case scroll(delay: TimeInterval, distance: CGFloat,
                    duration: TimeInterval, hold: TimeInterval)
        /// Reduce Motion: show one static truncated line, never scroll.
        case staticTruncated
    }

    static let fitHold: TimeInterval = 2.2
    static let scrollDelay: TimeInterval = 0.4
    static let scrollSpeed: CGFloat = 26 // pt/s
    static let scrollHold: TimeInterval = 0.5

    static func decide(textWidth: CGFloat,
                       viewportWidth: CGFloat,
                       reduceMotion: Bool) -> Decision {
        if reduceMotion {
            return .staticTruncated
        }
        let overflow = textWidth - viewportWidth
        guard overflow > 0 else {
            return .fits(hold: fitHold)
        }
        return .scroll(
            delay: scrollDelay,
            distance: overflow,
            duration: TimeInterval(overflow / scrollSpeed),
            hold: scrollHold)
    }

    /// How long the reading reveal stays open before shrinking to resting.
    /// Reduce Motion reuses the fit hold so the static title stays readable.
    static func readingWindow(for decision: Decision) -> TimeInterval {
        switch decision {
        case .fits(let hold):
            return hold
        case .scroll(let delay, _, let duration, let hold):
            return delay + duration + hold
        case .staticTruncated:
            return fitHold
        }
    }
}
