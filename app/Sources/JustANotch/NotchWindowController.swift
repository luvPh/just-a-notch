import AppKit
import SwiftUI
import Combine

/// Hosting view that responds to the first click even when the panel isn't key,
/// so the media controls work without activating the app first.
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: Content) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError() }
}

/// Owns the notch panel: positions it over the physical notch, hosts the SwiftUI
/// island, toggles mouse pass-through so only the island is interactive, and
/// collapses on outside clicks.
@MainActor
final class NotchWindowController {
    private let panel: NotchPanel
    private let vm: NotchViewModel
    private let media: MediaService
    private let notifier: NotificationService
    private var bag = Set<AnyCancellable>()
    private var monitors: [Any] = []

    private var coreCenterX: CGFloat = 0
    private var screenTopY: CGFloat = 0

    init() {
        media = MediaService()
        notifier = NotificationService()
        vm = NotchViewModel(media: media, notifier: notifier)
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40))
        panel.contentView = ClickableHostingView(rootView: NotchRootView(vm: vm))
        panel.orderFrontRegardless()

        applyGeometry()
        layoutPanel()
        installMonitors()
        vm.start()

        // While expanded OR while a HUD banner is showing, the panel must receive
        // clicks (controls / tap-to-open-source-app).
        vm.$expanded.combineLatest(vm.$hudNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] exp, hud in
                if exp || hud != nil { self?.panel.ignoresMouseEvents = false }
                self?.updateHover()
            }.store(in: &bag)

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
        // Physical notch (camera) height = safe-area top when present; 38pt fallback.
        let safeTop = screen.safeAreaInsets.top
        vm.notchHeight = safeTop > 0 ? safeTop : 38
    }

    /// Surface bounding rect in screen (bottom-left origin) coordinates.
    private var islandScreenRect: CGRect {
        let w = vm.surfaceWidth, h = vm.surfaceHeight
        let centred = vm.expanded || vm.showingHUD
        let left: CGFloat = centred
            ? coreCenterX - w / 2
            : coreCenterX - vm.coreWidth / 2 - vm.leftReveal
        return CGRect(x: left, y: screenTopY - h, width: w, height: h)
    }

    /// The panel is a FIXED transparent canvas (widest × tallest state), positioned
    /// top-centre on the notch. Every state animates purely inside SwiftUI, top-anchored
    /// — exactly like the prototype — so nothing resizes the window and motion is smooth.
    /// Mouse pass-through outside the island keeps the transparent area click-through.
    private func layoutPanel() {
        let w = panelWidth
        let h = vm.maxSurfaceHeight
        let frame = CGRect(x: coreCenterX - w / 2, y: screenTopY - h, width: w, height: h)
        panel.setFrame(frame, display: true)
    }

    /// Contains the core-anchored surface at its widest asymmetric extent (reading
    /// left wing 150) and the expanded width.
    private var panelWidth: CGFloat { max(vm.coreWidth + 2 * 150, vm.expandedWidth) }

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
        // Clicks inside our own transparent panel but outside the island also collapse.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            guard let self, self.vm.expanded else { return e }
            if !self.islandScreenRect.contains(NSEvent.mouseLocation) { self.vm.collapse() }
            return e
        })
    }

    private func updateHover() {
        let inside = islandScreenRect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = (vm.expanded || vm.showingHUD) ? false : !inside
        let hover = inside && !vm.expanded
        if vm.hovering != hover { vm.hovering = hover }
    }

    func toggleVisibility() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
}
