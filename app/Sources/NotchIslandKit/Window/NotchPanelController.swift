// File: Sources/NotchIsland/Window/NotchPanelController.swift
import AppKit
import SwiftUI
import Combine
import QuartzCore

enum OutsideClickAction: Equatable {
    case ignore
    case collapseToCompact
}

enum NotchPanelInteraction {
    static func outsideClickAction(
        isExpanded: Bool,
        isPinned: Bool
    ) -> OutsideClickAction {
        isExpanded && !isPinned ? .collapseToCompact : .ignore
    }
}

enum NotchPanelFrame {
    static func target(
        screenFrame: CGRect,
        contentSize: CGSize,
        compactHeight: CGFloat,
        alignmentOffset: CGFloat
    ) -> CGRect {
        let width = max(contentSize.width, 180)
        let height = max(contentSize.height, compactHeight)
        let x = screenFrame.midX + alignmentOffset - width / 2
        let y = screenFrame.maxY - height
        return CGRect(
            x: x.rounded(),
            y: y.rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    /// Core-anchored compact frame: keeps the physical camera core stationary at
    /// `screenFrame.midX + alignmentOffset` regardless of asymmetric reveals.
    /// The X origin is rounded but the core centre is preserved because reveals
    /// and core width are whole points in every named state.
    static func compactTarget(
        screenFrame: CGRect,
        alignmentOffset: CGFloat,
        geometry: AsymmetricCompactGeometry,
        compactHeight: CGFloat
    ) -> CGRect {
        let width = geometry.totalWidth
        let height = max(compactHeight, 1)
        let x = AsymmetricCompactGeometryModel.panelOriginX(
            screenMidX: screenFrame.midX,
            alignmentOffset: alignmentOffset,
            geometry: geometry
        )
        let y = screenFrame.maxY - height
        return CGRect(
            x: x.rounded(),
            y: y.rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }

    static func phaseTarget(
        phase: IslandMotionPhase,
        currentFrame: CGRect,
        compactFrame: CGRect,
        expandedFrame: CGRect,
        screenFrame: CGRect
    ) -> CGRect {
        switch phase {
        case .resting:
            return compactFrame
        case .expanding:
            let availableOvershoot = max(0, screenFrame.width - expandedFrame.width)
            let overshoot = min(IslandMotion.expansionOvershoot, availableOvershoot)
            let width = expandedFrame.width + overshoot
            let unclampedX = expandedFrame.midX - width / 2
            let x = min(
                max(unclampedX, screenFrame.minX),
                screenFrame.maxX - width
            )
            return CGRect(
                x: x,
                y: expandedFrame.minY,
                width: width,
                height: expandedFrame.height
            )
        case .settled:
            return expandedFrame
        case .anticipatingClose:
            let width = min(
                currentFrame.width + IslandMotion.collapseAnticipationWidth,
                screenFrame.width
            )
            let height = max(
                1,
                currentFrame.height - IslandMotion.collapseAnticipationHeight
            )
            let unclampedX = currentFrame.midX - width / 2
            let x = min(
                max(unclampedX, screenFrame.minX),
                screenFrame.maxX - width
            )
            return CGRect(
                x: x,
                y: currentFrame.maxY - height,
                width: width,
                height: height
            )
        case .collapsing:
            return compactFrame
        }
    }
}

/// Owns the `NotchPanel`, hosts the SwiftUI island, and keeps the window
/// anchored to the top-centre of the target screen across geometry changes.
@MainActor
final class NotchPanelController {
    private let panel: NotchPanel
    private let viewModel: IslandViewModel
    private let settings: SettingsStore
    private let env: AppEnvironment
    private let motionCoordinator: IslandMotionCoordinator
    private let tabCoordinator: TabTransitionCoordinator
    private var hostingView: NSHostingView<AnyView>!
    private var expandedContentSize: CGSize?
    private var activeAnimatedPhase: IslandMotionPhase?
    private var activeAnimatedTarget: CGRect?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var lastObservedExpanded: Bool
    private var swiftUIReduceMotion = false

    init(env: AppEnvironment) {
        let provider = NotchGeometryProvider(
            simulateNotch: env.settings.simulateNotch,
            alignmentOffset: CGFloat(env.settings.notchAlignmentOffset)
        )
        let targetScreen = Self.preferredTargetScreen(using: provider)
        let initialGeometry = provider.geometry(for: targetScreen)
        let compactContentState: CompactContentState = env.mediaPanelVM.track == nil
            ? .quiet
            : .active
        let initialReducedMotion = env.settings.reduceAnimation
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let motionCoordinator = IslandMotionCoordinator(
            coreWidth: initialGeometry?.notchWidth,
            compactContentState: compactContentState,
            reduceMotion: initialReducedMotion
        )
        let initialContent = env.islandViewModel.state.content
            ?? IslandDefaultContent.select(mediaAvailable: env.mediaPanelVM.track != nil)
        let tabCoordinator = TabTransitionCoordinator(
            initial: initialContent,
            reduceMotion: initialReducedMotion
        )
        let initialContentSize = CGSize(
            width: motionCoordinator.geometry.surfaceWidth,
            height: CGFloat(env.settings.compactHeight)
        )
        let fallbackScreenFrame = NSScreen.main?.frame
            ?? NSScreen.screens.first?.frame
            ?? CGRect(x: 0, y: 0, width: initialContentSize.width, height: initialContentSize.height)
        let initialFrame = NotchPanelFrame.target(
            screenFrame: initialGeometry?.screenFrame ?? fallbackScreenFrame,
            contentSize: initialContentSize,
            compactHeight: CGFloat(env.settings.compactHeight),
            alignmentOffset: CGFloat(env.settings.notchAlignmentOffset)
        )

        self.env = env
        self.viewModel = env.islandViewModel
        self.settings = env.settings
        self.panel = NotchPanel(contentRect: initialFrame)
        self.motionCoordinator = motionCoordinator
        self.tabCoordinator = tabCoordinator
        self.lastObservedExpanded = env.islandViewModel.state.isExpandedLike

        let root = IslandRootView(
            viewModel: viewModel,
            settings: settings,
            mediaViewModel: env.mediaPanelVM,
            motionCoordinator: motionCoordinator,
            tabCoordinator: tabCoordinator,
            env: env
        ) { [weak self] size, includesExpanded in
            self?.updateContentSize(size, includesExpanded: includesExpanded)
        } onKeyboardFocusChanged: { [weak self] focused in
            self?.setAcceptsKeyboard(focused)
        } onReduceMotionChanged: { [weak self] reduced in
            self?.setSwiftUIReduceMotion(reduced)
        }
        hostingView = NSHostingView(rootView: AnyView(root))
        hostingView.wantsLayer = true
        panel.contentView = hostingView

        registerObservers()
        reposition()
        panel.orderFrontRegardless()
    }

    // MARK: - Geometry

    private static func preferredTargetScreen(
        using provider: NotchGeometryProvider
    ) -> NSScreen? {
        let screens = NSScreen.screens
        let mainIndex = screens.firstIndex { $0 == NSScreen.main }
        guard let index = NotchGeometryProvider.preferredScreenIndex(
            notchWidths: screens.map { provider.physicalNotchWidth(of: $0) },
            mainIndex: mainIndex
        ) else { return nil }
        return screens[index]
    }

    private func targetScreen(using provider: NotchGeometryProvider) -> NSScreen? {
        Self.preferredTargetScreen(using: provider)
    }

    func reposition(animated: Bool = false) {
        guard let geometry = refreshGeometry() else {
            Log.window.error("No screen geometry available; hiding panel")
            panel.orderOut(nil)
            return
        }

        let expanded = viewModel.state.isExpandedLike
        let contentSize: CGSize
        if expanded, let expandedContentSize {
            contentSize = expandedContentSize
        } else if expanded {
            contentSize = CGSize(
                width: CGFloat(settings.expandedWidth),
                height: max(panel.frame.height, CGFloat(settings.compactHeight))
            )
        } else {
            contentSize = compactContentSize
        }
        let frame = NotchPanelFrame.target(
            screenFrame: geometry.screenFrame,
            contentSize: contentSize,
            compactHeight: CGFloat(settings.compactHeight),
            alignmentOffset: CGFloat(settings.notchAlignmentOffset)
        )

        if animated && !prefersReducedMotion {
            animate(
                frame: frame,
                duration: IslandMotion.expansionDuration,
                timingFunction: CAMediaTimingFunction(
                    controlPoints: 0.23,
                    1,
                    0.32,
                    1
                )
            )
        } else {
            applyExact(frame: frame)
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private var prefersReducedMotion: Bool {
        settings.reduceAnimation
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            || swiftUIReduceMotion
    }

    private var compactContentSize: CGSize {
        CGSize(
            width: motionCoordinator.compactEnvelopeGeometry.totalWidth,
            height: CGFloat(settings.compactHeight)
        )
    }

    /// Core-anchored compact frame sized to the fixed envelope (widest reveal),
    /// so the window does not resize during the reading reveal.
    private func compactFrame(screenFrame: CGRect) -> CGRect {
        NotchPanelFrame.compactTarget(
            screenFrame: screenFrame,
            alignmentOffset: CGFloat(settings.notchAlignmentOffset),
            geometry: motionCoordinator.compactEnvelopeGeometry,
            compactHeight: CGFloat(settings.compactHeight)
        )
    }

    /// Reading window (seconds) for a track's title, measured with the same font
    /// the compact title uses, so the reveal stays open long enough to read.
    private func readingWindow(for track: MediaTrack) -> TimeInterval {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let width = (track.title as NSString)
            .size(withAttributes: [.font: font]).width
        let decision = CompactTitleMarqueePolicy.decide(
            textWidth: width, viewportWidth: 112, reduceMotion: prefersReducedMotion)
        return CompactTitleMarqueePolicy.readingWindow(for: decision)
    }

    private func refreshGeometry() -> NotchGeometry? {
        let provider = NotchGeometryProvider(
            simulateNotch: settings.simulateNotch,
            alignmentOffset: CGFloat(settings.notchAlignmentOffset)
        )
        guard let geometry = provider.geometry(for: targetScreen(using: provider)) else {
            return nil
        }
        if motionCoordinator.geometry.coreWidth != geometry.notchWidth {
            motionCoordinator.setCoreWidth(geometry.notchWidth)
        }
        return geometry
    }

    private func targetFrames() -> (
        geometry: NotchGeometry,
        compact: CGRect,
        expanded: CGRect
    )? {
        guard let geometry = refreshGeometry(), let expandedContentSize else {
            return nil
        }
        let compact = compactFrame(screenFrame: geometry.screenFrame)
        let expanded = NotchPanelFrame.target(
            screenFrame: geometry.screenFrame,
            contentSize: expandedContentSize,
            compactHeight: CGFloat(settings.compactHeight),
            alignmentOffset: CGFloat(settings.notchAlignmentOffset)
        )
        return (geometry, compact, expanded)
    }

    private func applyShellPhase(_ phase: IslandMotionPhase) {
        if phase == .resting {
            guard let geometry = refreshGeometry() else { return }
            applyExact(frame: compactFrame(screenFrame: geometry.screenFrame))
            return
        }

        guard let frames = targetFrames() else { return }
        let target = NotchPanelFrame.phaseTarget(
            phase: phase,
            currentFrame: panel.frame,
            compactFrame: frames.compact,
            expandedFrame: frames.expanded,
            screenFrame: frames.geometry.screenFrame
        )

        guard !prefersReducedMotion else {
            applyExact(frame: viewModel.state.isExpandedLike ? frames.expanded : frames.compact)
            return
        }

        switch phase {
        case .resting:
            applyExact(frame: frames.compact)
        case .expanding:
            animateShellPhase(
                .expanding,
                frame: target,
                duration: IslandMotion.expansionDuration,
                timingFunction: CAMediaTimingFunction(
                    controlPoints: 0.23,
                    1,
                    0.32,
                    1
                )
            )
        case .settled:
            applyExact(frame: frames.expanded)
        case .anticipatingClose:
            animateShellPhase(
                .anticipatingClose,
                frame: target,
                duration: IslandMotion.collapseAnticipationDuration,
                timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)
            )
        case .collapsing:
            animateShellPhase(
                .collapsing,
                frame: target,
                duration: IslandMotion.collapseDuration,
                timingFunction: CAMediaTimingFunction(
                    controlPoints: 0.77,
                    0,
                    0.175,
                    1
                )
            )
        }
    }

    private func animateShellPhase(
        _ phase: IslandMotionPhase,
        frame: CGRect,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        if activeAnimatedPhase == phase {
            if phase == .anticipatingClose { return }
            if let activeAnimatedTarget,
               abs(activeAnimatedTarget.minX - frame.minX) < 0.5,
               abs(activeAnimatedTarget.minY - frame.minY) < 0.5,
               abs(activeAnimatedTarget.width - frame.width) < 0.5,
               abs(activeAnimatedTarget.height - frame.height) < 0.5 {
                return
            }
        }
        activeAnimatedPhase = phase
        activeAnimatedTarget = frame
        animate(frame: frame, duration: duration, timingFunction: timingFunction)
    }

    private func animate(
        frame: CGRect,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        // `panel.frame` above is the current visible frame. AppKit retargets
        // this animator transaction from that presentation instead of a stale
        // logical endpoint when a phase is interrupted.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func applyExact(frame: CGRect) {
        activeAnimatedPhase = nil
        activeAnimatedTarget = nil
        hostingView?.layer?.removeAllAnimations()
        hostingView?.layer?.setAffineTransform(.identity)
        panel.setFrame(frame, display: true, animate: false)
    }

    func toggleVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            reposition()
        }
    }

    private func updateContentSize(_ size: CGSize, includesExpanded: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        guard includesExpanded else {
            if motionCoordinator.phase == .resting {
                applyShellPhase(.resting)
            }
            return
        }

        if let expandedContentSize,
           abs(size.width - expandedContentSize.width) < 0.5,
           abs(size.height - expandedContentSize.height) < 0.5 { return }
        expandedContentSize = size
        applyShellPhase(motionCoordinator.phase)
    }

    private func setSwiftUIReduceMotion(_ reduced: Bool) {
        guard swiftUIReduceMotion != reduced else { return }
        swiftUIReduceMotion = reduced
        updateCoordinatorReduceMotion()
    }

    private func updateCoordinatorReduceMotion() {
        let reduced = prefersReducedMotion
        let shellChanged = motionCoordinator.reduceMotion != reduced
        let tabsChanged = tabCoordinator.reduceMotion != reduced
        motionCoordinator.reduceMotion = reduced
        tabCoordinator.reduceMotion = reduced

        guard reduced, shellChanged || tabsChanged else { return }
        if tabCoordinator.state.phase != .idle {
            tabCoordinator.request(target: tabCoordinator.state.target)
        }
        motionCoordinator.requestExpanded(viewModel.state.isExpandedLike)
        applyShellPhase(motionCoordinator.phase)
    }

    private func synchronizePassiveTabContent(_ content: IslandContent) {
        guard tabCoordinator.state.phase == .idle,
              tabCoordinator.state.target != content else { return }
        let configuredReduceMotion = tabCoordinator.reduceMotion
        tabCoordinator.reduceMotion = true
        tabCoordinator.request(target: content)
        tabCoordinator.reduceMotion = configuredReduceMotion
    }

    private func settleForExternalGeometryChange() {
        let expanded = viewModel.state.isExpandedLike
        let desiredPhase: IslandMotionPhase = expanded ? .settled : .resting
        if motionCoordinator.phase != desiredPhase {
            let configuredReduceMotion = motionCoordinator.reduceMotion
            motionCoordinator.reduceMotion = true
            motionCoordinator.requestExpanded(expanded)
            motionCoordinator.reduceMotion = configuredReduceMotion
        }
        reposition()
    }

    // MARK: - Focus control

    /// Allow the panel to accept keyboard input (search / settings / shortcut capture).
    func setAcceptsKeyboard(_ accepts: Bool) {
        panel.allowsKey = accepts
        if accepts { panel.makeKeyAndOrderFront(nil) }
    }

    // MARK: - Observers

    private func registerObservers() {
        let nc = NotificationCenter.default
        let center = NSWorkspace.shared.notificationCenter

        let repositionSelector: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.updateCoordinatorReduceMotion()
                self?.settleForExternalGeometryChange()
            }
        }

        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { note in repositionSelector(note) })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                            object: nil, queue: .main) { note in repositionSelector(note) })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil, queue: .main) { note in repositionSelector(note) })
        observers.append(center.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { note in repositionSelector(note) })

        // React to setting changes that affect geometry.
        settings.$simulateNotch.combineLatest(settings.$notchAlignmentOffset, settings.$expandedWidth, settings.$compactHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.settleForExternalGeometryChange() }
            .store(in: &cancellables)
        settings.$reduceAnimation
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCoordinatorReduceMotion() }
            .store(in: &cancellables)

        env.mediaPanelVM.$track
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                guard let self else { return }
                self.motionCoordinator.setCompactContentState(track == nil ? .quiet : .active)
                let identity = track.map { $0.sourceAppName + "|" + $0.title }
                let window = track.map { self.readingWindow(for: $0) } ?? 0
                self.motionCoordinator.updateMediaIdentity(identity, readingWindow: window)
            }
            .store(in: &cancellables)

        // Reframe the compact window only when the fixed envelope changes (media
        // appears/disappears) — never during the reading reveal, which animates
        // inside SwiftUI so the window stays put and the motion is smooth.
        motionCoordinator.$asymmetricGeometry
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.motionCoordinator.phase == .resting,
                      let geometry = self.refreshGeometry() else { return }
                let target = self.compactFrame(screenFrame: geometry.screenFrame)
                if target != self.panel.frame {
                    self.applyExact(frame: target)
                }
            }
            .store(in: &cancellables)

        motionCoordinator.$geometry
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self,
                      self.motionCoordinator.phase == .resting
                        || self.motionCoordinator.phase == .collapsing else { return }
                self.applyShellPhase(self.motionCoordinator.phase)
            }
            .store(in: &cancellables)

        motionCoordinator.$phase
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.applyShellPhase(phase)
            }
            .store(in: &cancellables)

        // Ignore the click that launched/restored the app. Without this short
        // delay, the global monitor can collapse a newly shown panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                    let pinned: Bool
                    if case .pinned = self.viewModel.state {
                        pinned = true
                    } else {
                        pinned = false
                    }
                    switch NotchPanelInteraction.outsideClickAction(
                        isExpanded: self.viewModel.state.isExpandedLike,
                        isPinned: pinned
                    ) {
                    case .ignore:
                        break
                    case .collapseToCompact:
                        self.viewModel.dismiss()
                    }
                }
            }
        }

        viewModel.$state
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if let content = state.content {
                    self.synchronizePassiveTabContent(content)
                }
                let expanded = state.isExpandedLike
                guard expanded != self.lastObservedExpanded else { return }
                self.lastObservedExpanded = expanded
                self.motionCoordinator.requestExpanded(expanded)
            }
            .store(in: &cancellables)
    }

    deinit {
        let nc = NotificationCenter.default
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0); center.removeObserver($0) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }
}
