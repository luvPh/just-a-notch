import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Mô hình

enum AnnotateTool: String, CaseIterable, Identifiable {
    case arrow, rect, ellipse, line, pen, highlight, text, counter, pixelate
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .pen: "scribble"
        case .highlight: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .pixelate: "squareshape.split.3x3"
        }
    }
    var title: String {
        switch self {
        case .arrow: "Mũi tên (A)"
        case .rect: "Khung (R)"
        case .ellipse: "Ellipse (O)"
        case .line: "Đường thẳng (L)"
        case .pen: "Bút (P)"
        case .highlight: "Highlight (H)"
        case .text: "Chữ (T)"
        case .counter: "Đánh số bước (N)"
        case .pixelate: "Làm mờ (B)"
        }
    }
    var key: KeyEquivalent {
        switch self {
        case .arrow: "a"; case .rect: "r"; case .ellipse: "o"; case .line: "l"; case .pen: "p"
        case .highlight: "h"; case .text: "t"; case .counter: "n"; case .pixelate: "b"
        }
    }
}

struct Mark: Identifiable {
    let id = UUID()
    var tool: AnnotateTool
    var points: [CGPoint]          // toạ độ ảnh (pt)
    var color: Color
    var width: CGFloat
    var text: String = ""
    var number: Int = 0

    var first: CGPoint { points.first ?? .zero }
    var last: CGPoint { points.last ?? .zero }
    var box: CGRect {
        CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
    }
}

@MainActor
final class AnnotateModel: ObservableObject {
    let shot: Shot
    let pixelated: CGImage?
    @Published var marks: [Mark] = []
    @Published var redoStack: [Mark] = []
    @Published var draft: Mark?
    @Published var tool: AnnotateTool = .arrow
    @Published var color: Color = AnnotateModel.palette[0]
    @Published var width: CGFloat = 4
    @Published var editingText: UUID?

    static let palette: [Color] = [
        Color(red: 1.00, green: 0.27, blue: 0.27), Color(red: 1.00, green: 0.58, blue: 0.16),
        Color(red: 1.00, green: 0.84, blue: 0.20), Color(red: 0.24, green: 0.80, blue: 0.40),
        Color(red: 0.20, green: 0.56, blue: 1.00), Color(red: 0.62, green: 0.40, blue: 1.00),
        .white, .black,
    ]

    init(shot: Shot) {
        self.shot = shot
        // Bản pixel hoá của cả ảnh — công cụ làm mờ chỉ việc cắt vùng từ bản này.
        let ci = CIImage(cgImage: shot.image)
        let f = CIFilter.pixellate()
        f.inputImage = ci.clampedToExtent()
        f.scale = Float(max(8, CGFloat(shot.image.width) / 90))
        f.center = .zero
        pixelated = f.outputImage.flatMap { CIContext().createCGImage($0.cropped(to: ci.extent), from: ci.extent) }
    }

    var nextNumber: Int { (marks.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1 }

    func commit(_ m: Mark) { marks.append(m); redoStack.removeAll() }
    func undo() { if let m = marks.popLast() { redoStack.append(m) } }
    func redo() { if let m = redoStack.popLast() { marks.append(m) } }

    /// Ảnh kết quả ở đúng độ phân giải gốc.
    func render() -> CGImage? {
        let view = AnnotatedImage(shot: shot, marks: marks, draft: nil, pixelated: pixelated)
            .frame(width: shot.pointSize.width, height: shot.pointSize.height)
        let r = ImageRenderer(content: view)
        r.scale = shot.scale
        return r.cgImage
    }
}

// MARK: - Vẽ

/// Ảnh gốc + các chú thích (dùng cho cả màn hình sửa lẫn xuất ảnh).
struct AnnotatedImage: View {
    let shot: Shot
    let marks: [Mark]
    let draft: Mark?
    let pixelated: CGImage?
    /// Mark chữ đang gõ — không vẽ (ô nhập đã hiển thị nó).
    var hidden: UUID? = nil

    var body: some View {
        let size = shot.pointSize
        Canvas { ctx, canvasSize in
            let k = canvasSize.width / size.width
            ctx.scaleBy(x: k, y: k)
            ctx.draw(Image(decorative: shot.image, scale: shot.scale), in: CGRect(origin: .zero, size: size))
            for m in marks where m.id != hidden { Self.draw(m, in: &ctx, size: size, shot: shot, pixelated: pixelated) }
            if let d = draft { Self.draw(d, in: &ctx, size: size, shot: shot, pixelated: pixelated) }
        }
    }

    static func draw(_ m: Mark, in ctx: inout GraphicsContext, size: CGSize, shot: Shot, pixelated: CGImage?) {
        let w = m.width
        let style = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        switch m.tool {
        case .arrow:
            let a = m.first, b = m.last
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 1 else { return }
            let ang = atan2(b.y - a.y, b.x - a.x)
            let head = max(14, w * 4.2)
            let base = CGPoint(x: b.x - cos(ang) * head * 0.8, y: b.y - sin(ang) * head * 0.8)
            var shadow = ctx
            shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, y: 1))
            var shaft = Path(); shaft.move(to: a); shaft.addLine(to: base)
            shadow.stroke(shaft, with: .color(m.color), style: style)
            var tip = Path()
            tip.move(to: b)
            tip.addLine(to: CGPoint(x: b.x - cos(ang - 0.45) * head, y: b.y - sin(ang - 0.45) * head))
            tip.addLine(to: CGPoint(x: b.x - cos(ang + 0.45) * head, y: b.y - sin(ang + 0.45) * head))
            tip.closeSubpath()
            shadow.fill(tip, with: .color(m.color))
        case .rect:
            ctx.stroke(Path(roundedRect: m.box, cornerRadius: 4), with: .color(m.color), style: style)
        case .ellipse:
            ctx.stroke(Path(ellipseIn: m.box), with: .color(m.color), style: style)
        case .line:
            var p = Path(); p.move(to: m.first); p.addLine(to: m.last)
            ctx.stroke(p, with: .color(m.color), style: style)
        case .pen, .highlight:
            var p = Path()
            p.addLines(m.points)
            if m.tool == .highlight {
                var c = ctx
                c.blendMode = .multiply
                c.stroke(p, with: .color(m.color.opacity(0.45)),
                         style: StrokeStyle(lineWidth: w * 4, lineCap: .butt, lineJoin: .round))
            } else {
                ctx.stroke(p, with: .color(m.color), style: style)
            }
        case .text:
            guard !m.text.isEmpty else { return }
            var c = ctx
            c.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, y: 1))
            c.draw(Text(m.text).font(.system(size: textSize(w), weight: .bold)).foregroundColor(m.color),
                   at: m.first, anchor: .topLeading)
        case .counter:
            let r = max(11, w * 2.6)
            let circle = Path(ellipseIn: CGRect(x: m.first.x - r, y: m.first.y - r, width: 2 * r, height: 2 * r))
            var c = ctx
            c.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, y: 1))
            c.fill(circle, with: .color(m.color))
            ctx.stroke(circle, with: .color(.white), lineWidth: max(1.5, r * 0.12))
            ctx.draw(Text("\(m.number)").font(.system(size: r * 1.1, weight: .heavy, design: .rounded))
                        .foregroundColor(m.color == .white ? .black : .white),
                     at: m.first, anchor: .center)
        case .pixelate:
            guard let px = pixelated, m.box.width > 1, m.box.height > 1 else { return }
            var c = ctx
            c.clip(to: Path(roundedRect: m.box, cornerRadius: 3))
            c.draw(Image(decorative: px, scale: shot.scale), in: CGRect(origin: .zero, size: size))
        }
    }

    static func textSize(_ w: CGFloat) -> CGFloat { 12 + w * 3 }
}

// MARK: - Cửa sổ

@MainActor
enum AnnotateWindow {
    private static var windows: [NSWindow] = []

    static func open(_ shot: Shot) {
        let model = AnnotateModel(shot: shot)
        let screen = ScreenshotController.screenUnderMouse.visibleFrame
        var size = shot.pointSize
        let k = min(1, (screen.width * 0.8) / size.width, (screen.height * 0.8 - 60) / size.height)
        size = CGSize(width: max(560, size.width * k + 40), height: size.height * k + 100)
        let w = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Chú thích ảnh"
        w.titlebarAppearsTransparent = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: AnnotateView(model: model, close: { [weak w] in w?.close() }))
        w.center()
        windows.append(w)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { n in
            let closing = n.object as? NSWindow
            Task { @MainActor in windows.removeAll { $0 === closing } }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct AnnotateView: View {
    @ObservedObject var model: AnnotateModel
    let close: () -> Void
    @State private var textDraft = ""
    @FocusState private var textFocus: Bool
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.leading, 78).padding(.trailing, 12)   // chừa nút đèn giao thông
                .frame(height: 46)
                .background(Color(white: 0.11))
            GeometryReader { geo in
                let size = model.shot.pointSize
                let k = min(geo.size.width / size.width, geo.size.height / size.height, 1)
                let shown = CGSize(width: size.width * k, height: size.height * k)
                ZStack(alignment: .topLeading) {
                    AnnotatedImage(shot: model.shot, marks: model.marks, draft: model.draft, pixelated: model.pixelated,
                                   hidden: model.editingText)
                        .frame(width: shown.width, height: shown.height)
                        .contentShape(Rectangle())
                        .gesture(drawGesture(k: k))
                    textEditor(k: k)
                }
                .frame(width: shown.width, height: shown.height)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .background(Color(white: 0.07))
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(.black.opacity(0.8)))
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(minWidth: 560, minHeight: 300)
    }

    // MARK: Thanh công cụ

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnotateTool.allCases) { t in
                    Button { model.tool = t; commitText() } label: {
                        Image(systemName: t.symbol).font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(model.tool == t ? Color.black : .white.opacity(0.85))
                            .background(RoundedRectangle(cornerRadius: 7).fill(model.tool == t ? Color.white : .clear))
                    }
                    .buttonStyle(.plain).help(t.title)
                    .keyboardShortcut(t.key, modifiers: [])
                }
            }
            divider
            HStack(spacing: 5) {
                ForEach(Array(AnnotateModel.palette.enumerated()), id: \.offset) { _, c in
                    Button { model.color = c } label: {
                        Circle().fill(c).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                            .padding(3)
                            .overlay(Circle().strokeBorder(.white, lineWidth: model.color == c ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            divider
            HStack(spacing: 2) {
                ForEach([2.0, 4.0, 7.0], id: \.self) { w in
                    Button { model.width = w } label: {
                        Capsule().fill(.white).frame(width: 14, height: w * 0.8 + 1)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(model.width == w ? .white.opacity(0.2) : .clear))
                    }
                    .buttonStyle(.plain).help("Độ dày nét")
                }
            }
            divider
            iconButton("arrow.uturn.backward", "Hoàn tác (⌘Z)") { model.undo() }
                .keyboardShortcut("z", modifiers: .command).disabled(model.marks.isEmpty)
            iconButton("arrow.uturn.forward", "Làm lại (⇧⌘Z)") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(model.redoStack.isEmpty)
            Spacer(minLength: 8)
            textButton("Sao chép", primary: false) { export(copy: true) }.keyboardShortcut("c", modifiers: .command)
            textButton("Lưu", primary: false) { export(save: true) }.keyboardShortcut("s", modifiers: .command)
            textButton("Xong", primary: true) { export(copy: true, done: true) }.keyboardShortcut(.return, modifiers: .command)
        }
        .foregroundStyle(.white)
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 20) }

    private func iconButton(_ s: String, _ help: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: s).font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
        }
        .buttonStyle(.plain).help(help)
    }

    private func textButton(_ t: String, primary: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 12, weight: .semibold)).fixedSize()
                .foregroundStyle(primary ? Color.black : .white)
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(primary ? Color.white : .white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Vẽ

    private func drawGesture(k: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = CGPoint(x: v.location.x / k, y: v.location.y / k)
                let s = CGPoint(x: v.startLocation.x / k, y: v.startLocation.y / k)
                switch model.tool {
                case .text, .counter: return
                case .pen, .highlight:
                    if model.draft == nil { model.draft = Mark(tool: model.tool, points: [s], color: model.color, width: model.width) }
                    model.draft?.points.append(p)
                default:
                    model.draft = Mark(tool: model.tool, points: [s, p], color: model.color, width: model.width)
                }
            }
            .onEnded { v in
                let p = CGPoint(x: v.location.x / k, y: v.location.y / k)
                switch model.tool {
                case .counter:
                    model.commit(Mark(tool: .counter, points: [p], color: model.color, width: model.width, number: model.nextNumber))
                case .text:
                    commitText()
                    let m = Mark(tool: .text, points: [p], color: model.color, width: model.width)
                    model.marks.append(m)
                    model.editingText = m.id
                    textDraft = ""
                    DispatchQueue.main.async { textFocus = true }
                default:
                    if let d = model.draft, d.points.count >= 2,
                       hypot(d.last.x - d.first.x, d.last.y - d.first.y) > 3 || d.tool == .pen || d.tool == .highlight {
                        model.commit(d)
                    }
                }
                model.draft = nil
            }
    }

    @ViewBuilder private func textEditor(k: CGFloat) -> some View {
        if let id = model.editingText, let m = model.marks.first(where: { $0.id == id }) {
            TextField("Nhập chữ…", text: $textDraft)
                .textFieldStyle(.plain)
                .font(.system(size: AnnotatedImage.textSize(m.width) * k, weight: .bold))
                .foregroundStyle(m.color)
                .focused($textFocus)
                .fixedSize()
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .offset(x: m.first.x * k - 2, y: m.first.y * k - 2)
                .onSubmit { commitText() }
                .onChange(of: textDraft) { _, t in
                    if let i = model.marks.firstIndex(where: { $0.id == id }) { model.marks[i].text = t }
                }
        }
    }

    private func commitText() {
        guard let id = model.editingText else { return }
        model.editingText = nil
        textFocus = false
        if let i = model.marks.firstIndex(where: { $0.id == id }), model.marks[i].text.trimmingCharacters(in: .whitespaces).isEmpty {
            model.marks.remove(at: i)
        } else {
            model.redoStack.removeAll()
        }
    }

    // MARK: Xuất

    private func export(copy: Bool = false, save: Bool = false, done: Bool = false) {
        commitText()
        guard let cg = model.render() else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = model.shot.pointSize
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let edited = Shot(image: cg, scale: model.shot.scale, png: png, tempURL: model.shot.tempURL)
        try? png.write(to: model.shot.tempURL)
        let ctrl = ScreenshotController.shared
        if copy {
            ctrl.copy(edited)
            ctrl.clipboard?.addScreenshot(png: png, copy: false)
        }
        if save, let url = ctrl.save(edited) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        if done { close(); return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { toast = save ? "Đã lưu" : "Đã sao chép" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { toast = nil } }
    }
}
