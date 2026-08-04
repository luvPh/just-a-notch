// File: Sources/NotchIsland/App/AppDelegate.swift
import AppKit
import SwiftUI
import Combine

/// Menu-bar utility lifecycle: sets up the status item and the notch panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment()
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var onboardingWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar utility: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        panelController = NotchPanelController(env: environment)
        environment.toggleOverlayHandler = { [weak self] in self?.panelController?.toggleVisibility() }

        updateStatusItem(visible: environment.settings.showMenuBarIcon)
        environment.settings.$showMenuBarIcon
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateStatusItem(visible: $0) }
            .store(in: &cancellables)

        environment.registerDefaultShortcuts()
        if !environment.settings.didCompleteOnboarding {
            presentOnboarding()
        }
        Log.app.info("Notch Island launched")
    }

    private func presentOnboarding() {
        let view = OnboardingView(settings: environment.settings, env: environment) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            NSApp.setActivationPolicy(.accessory) // back to menu-bar utility
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Welcome"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        NSApp.setActivationPolicy(.regular) // show a real window during onboarding
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                   accessibilityDescription: "Notch Island")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show/Hide Island", action: #selector(toggleIsland), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Restart Overlay", action: #selector(restartOverlay), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Notch Island", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        item.menu = menu
        statusItem = item
    }

    private func updateStatusItem(visible: Bool) {
        if visible {
            setupStatusItem()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Actions

    @objc private func toggleIsland() {
        environment.toggleIsland()
    }

    @objc private func restartOverlay() {
        panelController = nil
        panelController = NotchPanelController(env: environment)
        environment.toggleOverlayHandler = { [weak self] in self?.panelController?.toggleVisibility() }
    }

    @objc private func openSettings() {
        // Phase 7 hosts a full Settings window; for now open the SwiftUI Settings scene.
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
