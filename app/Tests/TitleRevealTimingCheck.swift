import Foundation

private func assertEqual(_ actual: TimeInterval, _ expected: TimeInterval,
                         _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    guard abs(actual - expected) < 0.0001 else {
        fatalError("\(file):\(line): \(message); expected \(expected), got \(actual)")
    }
}

@main
struct TitleRevealTimingCheck {
    static func main() {
        let longMarquee = CompactTitleMarqueePlan(textWidth: 211, viewport: 111)
        assertEqual(longMarquee.overflow, 100, "marquee overflow must be available without a layout pass")
        assertEqual(longMarquee.panDuration, 100 / 34, "long title pan duration must use the measured overflow")

        let shortTitle = TitleRevealTiming(pan: 0)
        assertEqual(shortTitle.trailingHold, 6, "short title should remain visible for six seconds")
        assertEqual(shortTitle.retractionDelay, 6, "short title should retract after six seconds")

        let longTitle = TitleRevealTiming(pan: 5)
        assertEqual(longTitle.trailingHold, 2, "long title should hold its trailing edge for two seconds")
        assertEqual(longTitle.retractionDelay, 7, "long title should retract after pan and hold")
    }
}
