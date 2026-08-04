import SwiftUI

/// Audio-like spectrum: slim bars packed tight, each driven by a sum of detuned
/// harmonics shaped for punchy, irregular peaks. Static under Reduce Motion.
struct OrganicWaveform: View {
    var active: Bool
    var reduceMotion: Bool = false
    var tint: Color = Color(red: 0.96, green: 0.36, blue: 0.33)
    var bars: Int = 6

    private let amp:   [Double] = [0.55, 0.78, 0.95, 1.0, 0.9, 0.72, 0.58]
    private let speed: [Double] = [6.4, 8.5, 7.2, 9.0, 7.6, 8.0, 6.8]
    private let phase: [Double] = [0.0, 1.3, 2.6, 0.7, 3.1, 1.9, 4.0]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !active || reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let n = max(1, bars)
                let barW: CGFloat = 2.0
                let gap: CGFloat = 1.4
                let total = barW * CGFloat(n) + gap * CGFloat(n - 1)
                let startX = (size.width - total) / 2
                let minH: CGFloat = 2.5
                for i in 0..<n {
                    let a = amp[i % amp.count]
                    let s = speed[i % speed.count], ph = phase[i % phase.count]
                    let p: Double
                    if reduceMotion {
                        p = a * 0.6
                    } else {
                        let v = sin(t * s + ph) * 0.60
                              + sin(t * s * 1.73 + ph * 2.1) * 0.28
                              + sin(t * s * 2.91 + ph * 0.7) * 0.18
                        let norm = min(1, max(0, (v + 1.06) / 2.12))
                        p = a * pow(norm, 1.5)
                    }
                    let h = minH + CGFloat(p) * (size.height - minH)
                    let x = startX + CGFloat(i) * (barW + gap)
                    let r = CGRect(x: x, y: (size.height - h) / 2, width: barW, height: h)
                    ctx.fill(Path(roundedRect: r, cornerRadius: barW / 2), with: .color(tint))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
