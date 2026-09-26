import XCTest
import SwiftUI
@testable import JustANotch

/// Render cửa sổ học ra PNG (offscreen) để soát layout — chỉ chạy khi LEARN_SNAP=<dir>.
@MainActor
final class LearnSnapshotCheck: XCTestCase {
    func testSnapshots() throws {
        guard let out = ProcessInfo.processInfo.environment["LEARN_SNAP"] else { throw XCTSkip("no LEARN_SNAP") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seedURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Learn/seed_b1b2.json")
        let seed = try JSONDecoder().decode([LearnWord].self, from: Data(contentsOf: seedURL))
        let store = LearnStore(dir: dir, seed: seed)
        for s in LearnSection.allCases {
            let v = NSHostingView(rootView: LearnWindowRoot(store: store, initial: s).frame(width: 980, height: 680))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = v
            w.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(s.rawValue).png"))
        }
        // Từ dài trong popup (bề rộng thật 400 − 2×22).
        let long = LearnWord(headword: "immaculate", pos: "adjective", ipaUK: "/ɪˈmæk.jə.lət/", ipaUS: "/ɪˈmæk.jə.lət/",
            senses: [LearnSense(guideword: "VERY CLEAN", level: "C2", defEN: "perfectly clean and tidy",
                                defVI: "sạch bong, tinh tươm", examples: [LearnExample(en: "Her kitchen is always immaculate.", vi: "Bếp luôn sạch bong.")])])
        let card = NSHostingView(rootView: IntroCardView(word: long, sense: long.senses[0], compact: true, onGotIt: {}, onSkip: {}, onKnown: {})
            .environment(\.learnOnNotch, true).foregroundStyle(.white).frame(width: 356, height: 210).background(.black))
        let cw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 356, height: 210), styleMask: [.titled], backing: .buffered, defer: false)
        cw.contentView = card
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let crep = card.bitmapImageRepForCachingDisplay(in: card.bounds)!
        card.cacheDisplay(in: card.bounds, to: crep)
        try crep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/long.png"))

        // Màn hoàn thành (compact, bề rộng popup).
        let done = NSHostingView(rootView: DailyCompleteView(store: store, compact: true)
            .environment(\.learnOnNotch, true).foregroundStyle(.white).frame(width: 356, height: 120).background(.black))
        let dw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 356, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        dw.contentView = done
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let drep = done.bitmapImageRepForCachingDisplay(in: done.bounds)!
        done.cacheDisplay(in: done.bounds, to: drep)
        try drep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/done.png"))

        let panel = NSHostingView(rootView: LearnPanel(store: store).frame(width: 300, height: 230).background(.black))
        let pw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 230), styleMask: [.titled], backing: .buffered, defer: false)
        pw.contentView = panel
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = panel.bitmapImageRepForCachingDisplay(in: panel.bounds)!
        panel.cacheDisplay(in: panel.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/notch.png"))
    }
}
