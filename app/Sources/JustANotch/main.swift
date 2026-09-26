import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: NotchWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar utility, no Dock icon
        controller = NotchWindowController()
        setupStatusItem()
        if CommandLine.arguments.contains("--learn") { LearnWindowController.shared.show() }
        if CommandLine.arguments.contains("--learn-pop") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.controller?.popLearn() }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Just a Notch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Notch", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Mở cửa sổ học", action: #selector(openLearn), keyEquivalent: "l").target = self
        menu.addItem(withTitle: "Hiện một từ ngay", action: #selector(popLearn), keyEquivalent: "").target = self
        let pauseItem = NSMenuItem(title: "Tạm dừng popup học", action: nil, keyEquivalent: "")
        pauseItem.submenu = NSMenu()
        pauseItem.submenu?.delegate = self
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.cleanupShelf()
    }

    @objc private func toggle() { controller?.toggleVisibility() }
    @objc private func openLearn() { LearnWindowController.shared.show() }
    @objc private func popLearn() { controller?.popLearn() }

    /// Dựng lại submenu tạm dừng mỗi lần mở (mốc "hết hôm nay" + trạng thái hiện tại).
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = AppSettings.shared
        if let label = s.learnPauseLabel {
            menu.addItem(withTitle: label, action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(withTitle: "Tiếp tục ngay", action: #selector(resumeLearn), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        for (i, opt) in AppSettings.learnPauseOptions().enumerated() {
            let item = menu.addItem(withTitle: opt.0, action: #selector(pauseLearn(_:)), keyEquivalent: "")
            item.target = self; item.tag = i
        }
    }
    @objc private func pauseLearn(_ sender: NSMenuItem) {
        AppSettings.shared.learnPausedUntil = AppSettings.learnPauseOptions()[sender.tag].1
    }
    @objc private func resumeLearn() { AppSettings.shared.learnPausedUntil = nil }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
