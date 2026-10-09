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
                    .foregroundStyle(.ink.opacity(0.95)))
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

/// Icon nguồn nhạc ở wing trái, bấm để mở app/tab nguồn. Vùng bấm 30×30; hover →
/// icon phóng spring, quầng sáng màu của nguồn, badge ↗ báo "mở app"; nhấn → lún.
struct SourceIconButton: View {
    let sourceApp: String
    let reduceMotion: Bool
    let action: () -> Void
    @State private var hovering = false

    /// Màu thương hiệu gần đúng của nguồn đang phát.
    private var tint: Color {
        let n = sourceApp.lowercased()
        if n.contains("spotify") { return Color(red: 0.12, green: 0.84, blue: 0.38) }
        if n.contains("music") || n.contains("podcast") { return Color(red: 0.99, green: 0.33, blue: 0.47) }
        if SourceIcon.symbol(for: sourceApp) == "play.rectangle.fill" { return Color(red: 1.0, green: 0.22, blue: 0.2) }
        return Color(red: 0.62, green: 0.5, blue: 1.0)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(tint.opacity(hovering ? 0.55 : 0))
                    .frame(width: 26, height: 26)
                    .blur(radius: 7)
                SourceIcon(sourceApp: sourceApp, size: 18)
                    .scaleEffect(hovering ? 1.15 : 1)
                    .shadow(color: tint.opacity(hovering ? 0.8 : 0), radius: 5)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 6.5, weight: .heavy))
                    .foregroundStyle(.ink)
                    .frame(width: 11, height: 11)
                    .background(Circle().fill(.black))
                    .overlay(Circle().strokeBorder(.ink.opacity(0.35), lineWidth: 0.6))
                    .offset(x: 10, y: -8)
                    .opacity(hovering ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.4)
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(SourceIconPressStyle())
        .onHover { h in
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.6)) {
                hovering = h
            }
            (h ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
        .help("Mở \(sourceApp.isEmpty ? "nguồn phát" : sourceApp)")
    }
}

private struct SourceIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

/// One-pass marquee: shows the start of the title, slides through to the end,
/// then holds. Static if the title already fits.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 11, weight: .semibold)
    let viewport: CGFloat
    let onPanDuration: (TimeInterval) -> Void
    /// Chữ ngắn hơn khung thì canh giữa (dải phình) thay vì dính trái.
    var centerIfFits = false
    @State private var offset: CGFloat = 0

    var body: some View {
        let fits = Self.textWidth(text) <= viewport
        Text(text)
            .font(font).foregroundStyle(.ink).lineLimit(1).fixedSize()
            .offset(x: offset)
            .frame(width: viewport, alignment: centerIfFits && fits ? .center : .leading)
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
