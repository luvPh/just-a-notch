import SwiftUI

/// Lớp hiệu ứng thời tiết phủ nhẹ trong notch mở rộng (khi bật "Notch theo thời tiết"):
/// mưa rơi xiên, tuyết bay, mây trôi, nắng toả / sao lấp lánh. Không nhận chuột, rất mờ
/// để không tranh với nội dung tab.
struct WeatherAmbientLayer: View {
    let kind: WeatherKind
    let isDay: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                switch kind {
                case .rain, .drizzle, .thunder:
                    rain(&g, size, t, heavy: kind != .drizzle)
                    if kind == .thunder { flash(&g, size, t) }
                case .snow:
                    snow(&g, size, t)
                case .cloudy, .fog, .partly:
                    clouds(&g, size, t, dense: kind != .partly)
                    if kind == .partly { if isDay { sun(&g, size, t) } else { stars(&g, size, t) } }
                case .clear:
                    if isDay { sun(&g, size, t) } else { stars(&g, size, t) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Số giả ngẫu nhiên ổn định theo chỉ số hạt.
    private func rnd(_ i: Int, _ salt: Double) -> Double {
        let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return x - floor(x)
    }

    private func rain(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double, heavy: Bool) {
        let n = heavy ? 70 : 36
        for i in 0..<n {
            let speed = 260 + rnd(i, 1) * 160
            let len = (heavy ? 12 : 7) + rnd(i, 2) * 8
            let x0 = rnd(i, 3) * (s.width + 60)
            let y = (rnd(i, 4) * (s.height + 40) + t * speed).truncatingRemainder(dividingBy: s.height + 40) - 20
            let x = x0 - y * 0.18
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x - len * 0.18, y: y + len))
            g.stroke(p, with: .color(.ink.opacity(0.10 + rnd(i, 5) * 0.12)), lineWidth: 1)
        }
    }

    private func flash(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        // Chớp ngắn mỗi ~7s.
        let phase = t.truncatingRemainder(dividingBy: 7)
        guard phase < 0.18 else { return }
        g.fill(Path(CGRect(origin: .zero, size: s)), with: .color(.ink.opacity(0.08 * (1 - phase / 0.18))))
    }

    private func snow(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        for i in 0..<45 {
            let speed = 18 + rnd(i, 1) * 22
            let r = 1 + rnd(i, 2) * 1.8
            let y = (rnd(i, 3) * (s.height + 10) + t * speed).truncatingRemainder(dividingBy: s.height + 10) - 5
            let x = rnd(i, 4) * s.width + sin(t * 0.8 + Double(i)) * 8
            g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                   with: .color(.ink.opacity(0.18 + rnd(i, 5) * 0.2)))
        }
    }

    private func clouds(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double, dense: Bool) {
        var c = g
        c.addFilter(.blur(radius: 22))
        for i in 0..<(dense ? 5 : 3) {
            let w = 160 + rnd(i, 1) * 140
            let speed = 6 + rnd(i, 2) * 6
            let x = (rnd(i, 3) * (s.width + w) + t * speed).truncatingRemainder(dividingBy: s.width + w) - w
            let y = rnd(i, 4) * s.height * 0.7
            c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: w * 0.32)),
                   with: .color(.ink.opacity(dense ? 0.07 : 0.05)))
        }
    }

    private func sun(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        let center = CGPoint(x: s.width * 0.92, y: -10)
        let pulse = 1 + sin(t * 0.6) * 0.06
        g.fill(Path(ellipseIn: CGRect(x: center.x - 140 * pulse, y: center.y - 140 * pulse,
                                      width: 280 * pulse, height: 280 * pulse)),
               with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.5).opacity(0.18), .clear]),
                                     center: center, startRadius: 0, endRadius: 140 * pulse))
        // Tia nắng xoay rất chậm.
        for k in 0..<7 {
            let a = Double(k) / 7 * .pi + t * 0.03 + .pi * 0.5
            var p = Path()
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + cos(a) * 260, y: center.y + sin(a) * 260))
            g.stroke(p, with: .color(Color(red: 1, green: 0.88, blue: 0.6).opacity(0.035)), lineWidth: 18)
        }
    }

    private func stars(_ g: inout GraphicsContext, _ s: CGSize, _ t: Double) {
        for i in 0..<28 {
            let x = rnd(i, 1) * s.width, y = rnd(i, 2) * s.height * 0.8
            let tw = 0.5 + 0.5 * sin(t * (0.8 + rnd(i, 3) * 1.6) + Double(i))
            let r = 0.6 + rnd(i, 4) * 0.9
            g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                   with: .color(.ink.opacity(0.08 + tw * 0.25)))
        }
    }
}
