// File: Sources/JustANotch/UI/SlidingText.swift
import SwiftUI

/// Single-line text that slides horizontally to reveal overflowing content
/// instead of truncating with an ellipsis. Renders as a plain static label when
/// the text fits. When it overflows, it scrolls to the end and back a fixed
/// number of times (`loops`) — more passes for freshly-arrived items, one for a
/// re-view. Honors Reduce Motion by falling back to tail truncation.
///
/// The whole view is wrapped in a `GeometryReader` so it always takes exactly
/// the width its parent offers. The measuring `Text` uses `.fixedSize()` (so it
/// can overflow and be clipped) but lives *inside* that fixed-width frame — its
/// intrinsic width can never leak upward and stretch the notch.
struct SlidingText: View {
    let text: String
    let font: Font
    let color: Color
    /// How many there-and-back passes to run when the text overflows.
    var loops: Int = 1
    /// Height of the single visible line (keeps layout stable while animating).
    var lineHeight: CGFloat = 15

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var started = false

    private let leadPause: Double = 0.6
    private let endPause: Double = 0.4
    private let speed: CGFloat = 42   // points per second

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font).foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: !reduceMotion, vertical: false)
                    .truncationMode(.tail)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .onAppear { textWidth = g.size.width; attemptStart() }
                                .onChange(of: g.size.width) { _, v in textWidth = v; restart() }
                        }
                    )
                    .offset(x: reduceMotion ? 0 : offset)
            }
            .frame(width: geo.size.width, height: lineHeight, alignment: .leading)
            .clipped()
            .onAppear { containerWidth = geo.size.width; attemptStart() }
            .onChange(of: geo.size.width) { _, v in containerWidth = v }
        }
        .frame(height: lineHeight)
    }

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    private func restart() {
        started = false
        offset = 0
        attemptStart()
    }

    private func attemptStart() {
        guard !reduceMotion, !started else { return }
        guard textWidth > 0, containerWidth > 0, overflow > 1 else { return }
        started = true
        runPass(loops, distance: overflow + 6)
    }

    private func runPass(_ remaining: Int, distance: CGFloat) {
        guard remaining > 0, distance > 0 else { return }
        let dur = Double(distance) / Double(speed)
        withAnimation(.easeInOut(duration: dur).delay(leadPause)) { offset = -distance }
        DispatchQueue.main.asyncAfter(deadline: .now() + leadPause + dur + endPause) {
            guard started else { return }
            withAnimation(.easeInOut(duration: dur)) { offset = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.3) {
                guard started else { return }
                runPass(remaining - 1, distance: distance)
            }
        }
    }
}
