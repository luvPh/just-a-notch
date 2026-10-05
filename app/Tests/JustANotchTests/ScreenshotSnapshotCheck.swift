import XCTest
import SwiftUI
@testable import JustANotch

/// Ảnh xem trước giao diện chụp màn hình (chạy với NOTCH_SNAP=<dir>).
@MainActor
final class ScreenshotSnapshotCheck: XCTestCase {
    private func write<V: View>(_ v: V, _ size: CGSize, _ url: URL) throws {
        let host = NSHostingView(rootView: v.frame(width: size.width, height: size.height))
        let w = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        w.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    /// "Màn hình" giả 900×560 @2x vẽ bằng SwiftUI.
    private func fakeScreen() -> CGImage {
        let v = ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.3, blue: 0.5), Color(red: 0.8, green: 0.5, blue: 0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 10).fill(.white).frame(width: 420, height: 280).offset(x: -120, y: 20)
                .overlay(Text("Finder window").font(.title).foregroundStyle(.black).offset(x: -120, y: 20))
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15)).frame(width: 300, height: 200).offset(x: 220, y: -60)
        }.frame(width: 900, height: 560)
        let r = ImageRenderer(content: v); r.scale = 2
        return r.cgImage!
    }

    func testScreenshotUI() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOTCH_SNAP"] else { throw XCTSkip("no NOTCH_SNAP") }
        let img = fakeScreen()
        let size = CGSize(width: 900, height: 560)
        let model = SelectionModel()
        var sel = SelectionView(image: img, size: size,
                                windows: [.init(id: 1, rect: CGRect(x: 120, y: 160, width: 420, height: 280))],
                                model: model, finish: { _ in })
        sel.debugDrag = (CGPoint(x: 180, y: 150), CGPoint(x: 520, y: 380))
        try write(sel, size, URL(fileURLWithPath: "\(dir)/shot-select.png"))

        let model2 = SelectionModel(); model2.windowMode = true
        var win = SelectionView(image: img, size: size,
                                windows: [.init(id: 1, rect: CGRect(x: 120, y: 160, width: 420, height: 280))],
                                model: model2, finish: { _ in })
        win.debugDrag = (CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 300))
        try write(win, size, URL(fileURLWithPath: "\(dir)/shot-window.png"))

        let frameView = ZStack {
            Image(decorative: img, scale: 2).resizable()
            RecordingFrame(rect: CGRect(x: 180, y: 140, width: 420, height: 260), size: size)
        }
        try write(frameView, size, URL(fileURLWithPath: "\(dir)/rec-frame.png"))

        let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
        let shot = Shot(image: img, scale: 2, png: png, tempURL: URL(fileURLWithPath: "/tmp/x.png"))
        let am = AnnotateModel(shot: shot)
        let red = AnnotateModel.palette[0], blue = AnnotateModel.palette[4], yellow = AnnotateModel.palette[2]
        am.marks = [
            Mark(tool: .arrow, points: [CGPoint(x: 600, y: 420), CGPoint(x: 420, y: 300)], color: red, width: 4),
            Mark(tool: .rect, points: [CGPoint(x: 120, y: 160), CGPoint(x: 540, y: 440)], color: blue, width: 4),
            Mark(tool: .highlight, points: [CGPoint(x: 160, y: 250), CGPoint(x: 360, y: 250)], color: yellow, width: 4),
            Mark(tool: .counter, points: [CGPoint(x: 140, y: 180)], color: red, width: 4, number: 1),
            Mark(tool: .counter, points: [CGPoint(x: 700, y: 120)], color: red, width: 4, number: 2),
            Mark(tool: .text, points: [CGPoint(x: 620, y: 440)], color: .white, width: 4, text: "Bấm vào đây"),
            Mark(tool: .pixelate, points: [CGPoint(x: 250, y: 270), CGPoint(x: 420, y: 320)], color: red, width: 4),
        ]
        try write(AnnotateView(model: am, close: {}), CGSize(width: 1000, height: 700),
                  URL(fileURLWithPath: "\(dir)/shot-annotate.png"))
    }
}
