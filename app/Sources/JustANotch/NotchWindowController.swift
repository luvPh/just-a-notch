import AppKit
import SwiftUI
import Combine

/// Owns the notch panel: positions it over the physical notch, hosts the SwiftUI
/// island, toggles mouse pass-through so only the island is interactive, and
/// collapses on outside clicks.
@MainActor
final class NotchWindowController {
    private let panel: NotchPanel
    private let vm: NotchViewModel
    private let media: MediaService
    private var bag = Set<AnyCancellable>()
    private var monitors: [Any] = []

    private var coreCenterX: CGFloat = 0
    private var screenTopY: CGFloat = 0

    init() {
        media = MediaService()
        vm = NotchViewModel(media: media)
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40))
        panel.contentView = NSHostingView(rootView: NotchRootView(vm: vm))
        panel.orderFrontRegardless()

        applyGeometry()
        layoutPanel()
        installMonitors()
        vm.start()

        vm.$expanded
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in self?.handleExpandedChange(expanded) }
            .store(in: &bag)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.applyGeometry(); self?.layoutPanel() } }
    }

    // MARK: Geometry

    private func applyGeometry() {
        // Always target the screen that physically owns the notch (never NSScreen.main,
        // which follows the active app to an external display).
        let probe = NotchGeometryProvider(simulateNotch: false)
        let notchScreen = NSScreen.screens.first { probe.physicalNotchWidth(of: $0) != nil }
        let screen = notchScreen ?? NSScreen.main ?? NSScreen.screens.first
        let provider = NotchGeometryProvider(simulateNotch: notchScreen == nil)
        guard let screen, let geo = provider.geometry(for: screen) else { return }
        coreCenterX = geo.screenFrame.midX
        screenTopY = geo.screenFrame.maxY
        vm.coreWidth = geo.notchWidth
        vm.menuBarHeight = geo.notchHeight
    }

    /// Surface bounding rect in screen (bottom-left origin) coordinates.
    private var islandScreenRect: CGRect {
        let w = vm.surfaceWidth, h = vm.surfaceHeight
        let left: CGFloat = vm.expanded
            ? coreCenterX - w / 2
            : coreCenterX - vm.coreWidth / 2 - vm.leftReveal
        return CGRect(x: left, y: screenTopY - h, width: w, height: h)
    }

    private func layoutPanel() {
        // Width is FIXED (widest envelope) so expand/collapse only changes height →
        // the surface grows straight down from the notch, no horizontal snap.
        let w = max(compactEnvelopeWidth, vm.expandedWidth)
        let h = vm.expanded ? vm.expandedHeight : (vm.menuBarHeight + 4)
        let frame = CGRect(x: coreCenterX - w / 2, y: screenTopY - h, width: w, height: h)
        panel.setFrame(frame, display: true)
    }

    /// Compact envelope stays at the widest (reading) width so resting↔reading
    /// never resizes the window — motion happens purely in SwiftUI.
    private var compactEnvelopeWidth: CGFloat { 138 + vm.coreWidth + 54 }

    private func handleExpandedChange(_ expanded: Bool) {
        if expanded {
            layoutPanel()                         // grow immediately, then content springs in
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, !self.vm.expanded else { return }
                self.layoutPanel()                // shrink only after the collapse animation
            }
        }
    }

    // MARK: Mouse handling

    private func installMonitors() {
        let moved: (NSEvent) -> Void = { [weak self] _ in self?.updateHover() }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: moved) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] e in
            self?.updateHover(); return e })
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self, self.vm.expanded else { return }
            if !self.islandScreenRect.contains(NSEvent.mouseLocation) { self.vm.collapse() }
        } as Any)
    }

    private func updateHover() {
        let inside = islandScreenRect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = vm.expanded ? false : !inside
        let hover = inside && !vm.expanded
        if vm.hovering != hover { vm.hovering = hover }
    }

    func toggleVisibility() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
}
