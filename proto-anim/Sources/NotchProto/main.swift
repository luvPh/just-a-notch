import AppKit
import SwiftUI

// MARK: - Notch shape
//
// Real MacBook-notch style (NOT a floating Dynamic Island):
//   • top edge is FLUSH with the screen top (the bezel)
//   • top outer corners curve CONCAVE (inverse radius) so the surface melts into the bezel
//   • only the BOTTOM corners are convex/rounded
// Everything grows DOWN from the physical notch.

struct NotchShape: Shape {
    var bottom: CGFloat     // convex bottom-corner radius
    var inverse: CGFloat    // concave top-corner radius

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottom, inverse) }
        set { bottom = newValue.first; inverse = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let ir = max(0, min(inverse, rect.width / 2 - 1))
        let br = max(0, min(bottom, rect.height - ir - 1, rect.width / 2 - ir - 1))

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))                                   // flush top edge
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ir, y: rect.minY + ir),                    // concave top-right
                       control: CGPoint(x: rect.maxX - ir, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - ir, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ir - br, y: rect.maxY),                    // convex bottom-right
                       control: CGPoint(x: rect.maxX - ir, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + ir + br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ir, y: rect.maxY - br),                    // convex bottom-left
                       control: CGPoint(x: rect.minX + ir, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + ir, y: rect.minY + ir))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),                              // concave top-left
                       control: CGPoint(x: rect.minX + ir, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Phases

enum NotchPhase: String, CaseIterable, Identifiable {
    case quiet, mediaResting, mediaReading
    var id: String { rawValue }
    var label: String {
        switch self { case .quiet: "Quiet"; case .mediaResting: "Resting"; case .mediaReading: "Reading" }
    }
    var leftExtent: CGFloat {
        switch self { case .quiet: 90; case .mediaResting: 104; case .mediaReading: 224 }
    }
    var rightExtent: CGFloat {
        switch self { case .quiet: 90; case .mediaResting: 132; case .mediaReading: 132 }
    }
    var height: CGFloat { self == .quiet ? 34 : 42 }   // grows a touch below the menu bar when active
    var width: CGFloat { leftExtent + rightExtent }
    var showsMedia: Bool { self != .quiet }
    var showsTitle: Bool { self == .mediaReading }
}

enum ExpandedTab: String, CaseIterable, Identifiable {
    case media = "Media", files = "Files", alerts = "Alerts"
    var id: String { rawValue }
    var icon: String {
        switch self { case .media: "play.circle.fill"; case .files: "folder.fill"; case .alerts: "bell.fill" }
    }
}


struct NotifItem: Identifiable, Equatable {
    let id: Int
    let icon: String
    let tint: Color
    let app: String
    let title: String
    let message: String
    let time: String
}

let sampleNotifs: [NotifItem] = [
    .init(id: 1, icon: "message.fill", tint: Color(red: 0.30, green: 0.78, blue: 0.40),
          app: "Messages", title: "Minh", message: "Đi cà phê không, gọi giúp mày ly nhé?", time: "now"),
    .init(id: 2, icon: "envelope.fill", tint: Color(red: 0.30, green: 0.55, blue: 0.98),
          app: "Mail", title: "Figma", message: "Your export is ready to download", time: "2m"),
    .init(id: 3, icon: "calendar", tint: Color(red: 0.98, green: 0.35, blue: 0.35),
          app: "Calendar", title: "Design sync", message: "Starts in 10 minutes · Meet", time: "8m"),
    .init(id: 4, icon: "arrow.down.circle.fill", tint: Color(red: 0.60, green: 0.55, blue: 0.98),
          app: "Downloads", title: "reveal.mov", message: "Finished downloading", time: "15m"),
]

// MARK: - Root

struct RootView: View {
    @State private var phase: NotchPhase = .mediaResting
    @State private var expanded = false
    @State private var tab: ExpandedTab = .media
    @State private var bouncy = true
    @State private var reduceMotion = false
    @State private var notif: NotifItem? = nil
    @State private var notifIndex = 0
    @Namespace private var glue

    private let panelW: CGFloat = 470
    private let menuBarH: CGFloat = 34

    private var openSpring: Animation {
        if reduceMotion { return .easeInOut(duration: 0.22) }
        return bouncy ? .spring(response: 0.5, dampingFraction: 0.8)
                      : .spring(response: 0.42, dampingFraction: 1.0)
    }
    private var revealSpring: Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return bouncy ? .spring(response: 0.42, dampingFraction: 0.74)
                      : .spring(response: 0.38, dampingFraction: 1.0)
    }

    private var showingNotif: Bool { notif != nil && !expanded }
    private var surfaceW: CGFloat { expanded ? panelW : (showingNotif ? 376 : phase.width) }
    private var surfaceH: CGFloat { expanded ? panelHeight : (showingNotif ? 82 : phase.height) }
    // Tight per-tab heights (layout is known, like a real notch app) — no async measuring.
    private var panelHeight: CGFloat {
        switch tab { case .media: 182; case .files: 300; case .alerts: 360 }
    }
    private var bottomRadius: CGFloat { expanded ? 26 : (showingNotif ? 24 : (phase == .quiet ? 12 : 16)) }
    private var inverseRadius: CGFloat { expanded ? 14 : 10 }
    private var centerXOffset: CGFloat { (expanded || showingNotif) ? 0 : (phase.rightExtent - phase.leftExtent) / 2 }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.22),
                                    Color(red: 0.03, green: 0.04, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { backgroundTap() }

            fauxMenuBar

            // Top-pinned BY LAYOUT: the surface sits at the top of a full-height VStack and the
            // Spacer absorbs all growth downward. The top edge can never move, no matter how the
            // measured height animates.
            VStack(spacing: 0) {
                surface
                    // alignment: .top is critical — a plain .frame centres its content, so while the
                    // height springs the full-size panel would grow from the CENTRE and shove the top
                    // off-screen. Top alignment keeps the content pinned to the bezel; it grows DOWN.
                    .frame(width: surfaceW, height: surfaceH, alignment: .top)
                    .offset(x: centerXOffset)   // horizontal core-anchor (asymmetric compact reveal)
                    .animation(revealSpring, value: phase)
                    .animation(revealSpring, value: notif)
                    .animation(openSpring, value: expanded)
                    .animation(openSpring, value: tab)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack { Spacer(); controls.padding(.bottom, 26) }
        }
        .frame(minWidth: 780, minHeight: 480)
    }

    // Faux Mac menu bar so the notch reads as sitting in the "tai thỏ".
    private var fauxMenuBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "apple.logo").font(.system(size: 13, weight: .medium))
            Text("Finder").font(.system(size: 13, weight: .semibold))
            Text("File").font(.system(size: 13))
            Text("Edit").font(.system(size: 13))
            Spacer()
            Image(systemName: "battery.75").font(.system(size: 13))
            Image(systemName: "wifi").font(.system(size: 12))
            Text("9:41").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.55))
        .padding(.leading, 80)   // clear the traffic-light buttons
        .padding(.trailing, 18)
        .frame(height: menuBarH)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04))
    }

    private var surface: some View {
        let shape = NotchShape(bottom: bottomRadius, inverse: inverseRadius)
        return ZStack(alignment: .top) {
            shape.fill(.black)
                .overlay(shape.stroke(.white.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: expanded ? 30 : 14, y: expanded ? 16 : 7)

            if expanded {
                ExpandedPanel(tab: $tab, glue: glue, reduceMotion: reduceMotion, topInset: menuBarH)
                    .transition(.opacity)
            } else if let n = notif {
                NotificationBanner(item: n, topInset: menuBarH).transition(.opacity)
            } else {
                CompactContent(phase: phase, glue: glue, reduceMotion: reduceMotion)
                    .padding(.horizontal, 14)
                    .frame(width: phase.width, height: phase.height, alignment: .leading)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { surfaceTap() }
    }

    private func surfaceTap() {
        if expanded { return }
        if notif != nil { withAnimation(revealSpring) { notif = nil }; return } // tap banner → dismiss
        expand()
    }
    private func backgroundTap() {
        if expanded { collapse() }
        else if notif != nil { withAnimation(revealSpring) { notif = nil } }
    }
    private func expand() { withAnimation(openSpring) { notif = nil; expanded = true } }
    private func collapse() { withAnimation(openSpring) { expanded = false } }

    private func fireNotif() {
        guard !expanded else { return }
        let item = sampleNotifs[notifIndex % sampleNotifs.count]
        notifIndex += 1
        withAnimation(revealSpring) { notif = item }
        let shown = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            if notif?.id == shown { withAnimation(revealSpring) { notif = nil } }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(NotchPhase.allCases) { p in
                    Button(p.label) { if !expanded { phase = p } }
                        .buttonStyle(PillBtn(active: phase == p))
                        .opacity(expanded ? 0.3 : 1)
                }
                Button("Notify ⤵") { fireNotif() }
                    .buttonStyle(PillBtn(active: false))
                    .opacity(expanded ? 0.3 : 1)
            }
            HStack(spacing: 18) {
                Toggle("Bounce", isOn: $bouncy)
                Toggle("Reduce Motion", isOn: $reduceMotion)
            }
            .toggleStyle(.switch).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))

            Text(expanded ? "Click outside to collapse back into the notch."
                          : "Click the notch to expand it downward into a panel.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Compact content

struct CompactContent: View {
    let phase: NotchPhase
    let glue: Namespace.ID
    let reduceMotion: Bool
    var body: some View {
        HStack(spacing: 10) {
            if phase.showsMedia {
                AlbumArt().matchedGeometryEffect(id: "art", in: glue)
                    .frame(width: 28, height: 28)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
            if phase.showsTitle {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Weightless").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    Text("Marconi Union").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                }.lineLimit(1).fixedSize()
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if phase.showsMedia {
                Waveform(active: true, reduceMotion: reduceMotion)
                    .frame(width: 22, height: 18)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - Expanded panel

struct ExpandedPanel: View {
    @Binding var tab: ExpandedTab
    let glue: Namespace.ID
    let reduceMotion: Bool
    let topInset: CGFloat
    @Namespace private var tabNS

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                AlbumArt().matchedGeometryEffect(id: "art", in: glue).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weightless").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Text("Marconi Union").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                HStack(spacing: 16) {
                    Image(systemName: "backward.fill")
                    Image(systemName: "pause.fill").font(.system(size: 19))
                    Image(systemName: "forward.fill")
                }.font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
            }

            HStack(spacing: 8) {
                ForEach(ExpandedTab.allCases) { t in
                    let active = t == tab
                    HStack(spacing: 6) {
                        Image(systemName: t.icon).font(.system(size: 12, weight: .semibold))
                        Text(t.rawValue).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(active ? .black : .white.opacity(0.72))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background { if active { Capsule().fill(.white).matchedGeometryEffect(id: "tabpill", in: tabNS) } }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { tab = t } }
                }
                Spacer()
            }

            tabBody.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 26)
        .padding(.top, topInset - 6)   // keep header clear of the camera/notch zone
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)   // pin content to top; extra height (if any) sits below
    }

    @ViewBuilder private var tabBody: some View {
        switch tab {
        case .media:
            VStack(alignment: .leading, spacing: 10) {
                Capsule().fill(.white.opacity(0.16)).frame(height: 5)
                    .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 140, height: 5) }
                HStack { Text("1:42"); Spacer(); Text("-3:18") }
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        case .files:
            VStack(spacing: 8) {
                ForEach(["Design spec.pdf", "reveal.mov", "notch-render.swift", "notes.md"], id: \.self) { f in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill").foregroundStyle(.white.opacity(0.5))
                        Text(f).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        case .alerts:
            VStack(spacing: 8) {
                ForEach(sampleNotifs) { n in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(n.tint)
                            .frame(width: 30, height: 30)
                            .overlay(Image(systemName: n.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(n.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                                Spacer()
                                Text(n.time).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                            Text(n.message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

struct NotificationBanner: View {
    let item: NotifItem
    let topInset: CGFloat   // clear the physical-notch / camera zone at the top
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(item.tint)
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: item.icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(item.app).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
                Text(item.message).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, topInset)     // content drops BELOW the notch, never behind the camera
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Shared

struct AlbumArt: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.55, blue: 0.98),
                                          Color(red: 0.78, green: 0.42, blue: 0.92)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "music.note").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.9)))
    }
}

struct Waveform: View {
    let active: Bool
    let reduceMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0, paused: !active || reduceMotion)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let barW: CGFloat = 3, gap: CGFloat = 3.5
                let ph: [Double] = [0.0, 1.1, 2.3]
                for i in 0..<3 {
                    let p = reduceMotion ? 0.5 : (sin(t*6 + ph[i]) * 0.5 + 0.5)
                    let h = 5 + CGFloat(p) * (size.height - 5)
                    let x = CGFloat(i) * (barW + gap)
                    let r = CGRect(x: x, y: (size.height - h)/2, width: barW, height: h)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(.white.opacity(0.85)))
                }
            }
        }
    }
}

struct PillBtn: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? .black : .white.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - AppKit bootstrap

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 540),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Notch Animation Prototype — tai thỏ"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = .black
        w.center()
        w.contentView = NSHostingView(rootView: RootView())
        w.makeKeyAndOrderFront(nil)
        self.window = w
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
