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
            let sym = Self.symbol(for: sourceApp)
            let isVideo = sym == "play.rectangle.fill"
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: isVideo
                                        ? [Color(red: 1.0, green: 0.30, blue: 0.28),   // đỏ YouTube
                                           Color(red: 0.80, green: 0.09, blue: 0.12)]
                                        : [Color(red: 0.42, green: 0.55, blue: 0.98),
                                           Color(red: 0.78, green: 0.42, blue: 0.92)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(Image(systemName: sym)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95)))
                .offset(x: isVideo ? 2 : 0)   // nhích cả icon (nền + glyph) sang phải 2px
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

/// One-pass marquee: shows the start of the title, slides through to the end,
/// then holds. Static if the title already fits.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 11, weight: .semibold)
    let viewport: CGFloat
    let onPanDuration: (TimeInterval) -> Void
    @State private var offset: CGFloat = 0

    var body: some View {
        Text(text)
            .font(font).foregroundStyle(.white).lineLimit(1).fixedSize()
            .offset(x: offset)
            .frame(width: viewport, alignment: .leading)
            .clipped()
            .onAppear { schedule() }
            // New title: snap back to the start immediately (show the beginning),
            // then let it slide the overflow — never inherit the old scroll offset.
            .onChange(of: text) { _, _ in schedule() }
    }

    private func schedule() {
        let plan = CompactTitleMarqueePlan(textWidth: Self.textWidth(text), viewport: viewport)
        onPanDuration(plan.panDuration)
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }
        guard plan.overflow > 4 else { return }
        withAnimation(.easeInOut(duration: plan.panDuration)) { offset = -plan.overflow }
    }

    private static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}
