import SwiftUI

/// Icon of the app currently playing (Music / Spotify / browser…), resolved from
/// the running application. Falls back to a per-platform SF Symbol.
struct SourceIcon: View {
    let sourceApp: String
    var size: CGFloat = 18

    var body: some View {
        if let icon = Self.runningAppIcon(named: sourceApp) {
            Image(nsImage: icon).resizable().interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.55, blue: 0.98),
                                              Color(red: 0.78, green: 0.42, blue: 0.92)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(Image(systemName: Self.symbol(for: sourceApp))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95)))
        }
    }

    static func runningAppIcon(named name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName == name
        }?.icon
    }

    static func symbol(for app: String) -> String {
        let n = app.lowercased()
        if n.contains("music") || n.contains("spotify") || n.contains("podcast") { return "music.note" }
        if n.contains("youtube") || n.contains("safari") || n.contains("chrome")
            || n.contains("tv") || n.contains("video") { return "play.rectangle.fill" }
        return "waveform"
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// One-pass marquee: shows the start of the title, slides through to the end,
/// then holds. Static if the title already fits.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 11, weight: .semibold)
    let viewport: CGFloat
    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font).foregroundStyle(.white).lineLimit(1).fixedSize()
            .background(GeometryReader { g in
                Color.clear.preference(key: MarqueeWidthKey.self, value: g.size.width) })
            .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0; schedule() }
            .offset(x: offset)
            .frame(width: viewport, alignment: .leading)
            .clipped()
            .onAppear { schedule() }
    }

    private func schedule() {
        let overflow = max(0, textWidth - viewport)
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }
        guard overflow > 4 else { return }
        withAnimation(.easeInOut(duration: Double(overflow) / 34.0).delay(1.5)) { offset = -overflow }
    }
}
