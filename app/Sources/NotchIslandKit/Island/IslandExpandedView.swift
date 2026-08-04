// File: Sources/NotchIsland/Island/IslandExpandedView.swift
import SwiftUI
import AppKit

struct OrbitalPortalEffect: GeometryEffect {
    var progress: CGFloat
    private var directionSign: CGFloat

    init(progress: CGFloat, direction: TabTransitionDirection) {
        self.progress = progress
        directionSign = direction == .backward ? -1 : 1
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, directionSign) }
        set {
            progress = newValue.first
            directionSign = newValue.second
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let start = CGPoint.zero
        let control = CGPoint(x: directionSign * 18, y: -46)
        let end = CGPoint(x: 0, y: -82)
        let inverse = 1 - progress
        let x = inverse * inverse * start.x
            + 2 * inverse * progress * control.x
            + progress * progress * end.x
        let y = inverse * inverse * start.y
            + 2 * inverse * progress * control.y
            + progress * progress * end.y
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

private struct PortalAnimationCompletionObserver: AnimatableModifier {
    let targetValue: CGFloat
    let completion: () -> Void
    var animatableData: CGFloat {
        didSet {
            guard targetValue > 0,
                  abs(animatableData - targetValue) < 0.0001 else { return }
            DispatchQueue.main.async(execute: completion)
        }
    }

    init(observedValue: CGFloat, completion: @escaping () -> Void) {
        targetValue = observedValue
        animatableData = observedValue
        self.completion = completion
    }

    func body(content: Content) -> some View {
        content
    }
}

enum IslandPortalRequestMode: Equatable {
    case beginAtOrigin
    case retargetCurrentPresentation
}

enum IslandPortalPresentationPolicy {
    static func requestMode(
        hasVisiblePresentation: Bool
    ) -> IslandPortalRequestMode {
        hasVisiblePresentation ? .retargetCurrentPresentation : .beginAtOrigin
    }

    static func shouldDismiss(
        cancellationRequestID: UInt64,
        activePortalRequestID: UInt64,
        hasVisiblePresentation: Bool
    ) -> Bool {
        hasVisiblePresentation
            && cancellationRequestID > activePortalRequestID
    }
}

struct IslandExpandedPanelLayer: Identifiable, Equatable {
    let content: IslandContent

    var id: String {
        switch content {
        case .media: return "panel-media"
        case .systemStatus: return "panel-system"
        case .finderShelf: return "panel-finder"
        case .notification: return "panel-notification"
        }
    }
}

struct IslandExpandedPanelPresentation: Equatable {
    let yOffset: CGFloat
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double

    static let identity = IslandExpandedPanelPresentation(
        yOffset: 0,
        scale: 1,
        blur: 0,
        opacity: 1
    )
    static let outgoingTerminal = IslandExpandedPanelPresentation(
        yOffset: 12,
        scale: 0.965,
        blur: 5,
        opacity: 0
    )
    static let incomingStart = IslandExpandedPanelPresentation(
        yOffset: -12,
        scale: 1.035,
        blur: 5,
        opacity: 0
    )
}

struct IslandExpandedPanelAccess: Equatable {
    let allowsHitTesting: Bool
    let accessibilityHidden: Bool
}

struct IslandFeatureAvailability: Equatable {
    let media: Bool
    let systemStatus: Bool
    let finderShelf: Bool
}

enum IslandExpandedTabPolicy {
    static func isEnabled(
        _ content: IslandContent,
        availability: IslandFeatureAvailability
    ) -> Bool {
        switch content {
        case .media: return availability.media
        case .systemStatus: return availability.systemStatus
        case .finderShelf: return availability.finderShelf
        case .notification: return false
        }
    }
}

enum IslandExpandedTransition {
    static func layers(for state: TabTransitionState) -> [IslandExpandedPanelLayer] {
        guard isActive(state) else {
            return [IslandExpandedPanelLayer(content: state.target)]
        }
        return [
            IslandExpandedPanelLayer(content: state.source),
            IslandExpandedPanelLayer(content: state.target)
        ]
    }

    static func presentation(
        for content: IslandContent,
        state: TabTransitionState
    ) -> IslandExpandedPanelPresentation {
        guard isActive(state) else { return .identity }
        if content == state.source { return .outgoingTerminal }
        if content == state.target, state.phase == .outgoing { return .incomingStart }
        return .identity
    }

    static func access(
        for content: IslandContent,
        state: TabTransitionState
    ) -> IslandExpandedPanelAccess {
        guard isActive(state) else {
            let current = content == state.target
            return IslandExpandedPanelAccess(
                allowsHitTesting: current,
                accessibilityHidden: !current
            )
        }

        let current: Bool
        switch state.phase {
        case .outgoing:
            current = content == state.source
        case .portal, .incoming:
            current = content == state.target
        case .idle:
            current = content == state.target
        }
        return IslandExpandedPanelAccess(
            allowsHitTesting: current,
            accessibilityHidden: !current
        )
    }

    private static func isActive(_ state: TabTransitionState) -> Bool {
        state.phase != .idle
            && state.direction != .none
            && state.source != state.target
    }
}

/// The content area must reserve the space each tab needs. A generic 90pt
/// minimum caused System's fourth metric to overflow underneath the tab bar.
enum IslandExpandedLayout {
    static let railContents: [IslandContent] = [
        .media,
        .systemStatus,
        .finderShelf
    ]
    static let tabHitHeight: CGFloat = 58
    static let bottomRailHeight: CGFloat = 70

    static func expandedTopClearance(notchHeight: CGFloat) -> CGFloat {
        max(notchHeight, 32)
    }

    static func minimumPanelHeight(for content: IslandContent) -> CGFloat {
        switch content {
        case .systemStatus: return 230
        case .media: return 120
        case .finderShelf, .notification: return 90
        }
    }
}

/// Expanded state with a simple tab bar. Phase 1/2 ships placeholder panels for
/// each content mode; later phases wire real services behind the same tabs.
struct IslandExpandedView: View {
    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var tabCoordinator: TabTransitionCoordinator
    let env: AppEnvironment
    let content: IslandContent
    let pinned: Bool
    let reduceMotion: Bool
    let onKeyboardFocusChanged: (Bool) -> Void
    @State private var renderedPortalProgress: CGFloat = 0
    @State private var portalVisible = false
    @State private var portalTarget: IslandContent?
    @State private var portalDirection: TabTransitionDirection = .none
    @State private var portalAnimationToken: CGFloat = 0
    @State private var activePortalRequestID: UInt64 = 0

    private var tabs: [(IslandContent, String, String)] {
        IslandExpandedLayout.railContents.map { content in
            switch content {
            case .media:
                return (content, "Media", "play.circle")
            case .systemStatus:
                return (content, "System", "gauge.with.dots.needle.bottom.50percent")
            case .finderShelf:
                return (content, "Finder", "folder")
            case .notification:
                preconditionFailure("Notification is not a user-selectable rail tab")
            }
        }
    }

    private var featureAvailability: IslandFeatureAvailability {
        IslandFeatureAvailability(
            media: env.settings.mediaEnabled,
            systemStatus: env.settings.systemStatusEnabled,
            finderShelf: env.settings.finderShelfEnabled
        )
    }

    private var transitionState: TabTransitionState { tabCoordinator.state }

    private var transitionActive: Bool {
        transitionState.phase != .idle
            && transitionState.direction != .none
            && transitionState.source != transitionState.target
    }

    /// Height for the current transition (the taller of source/target so content
    /// does not clip mid-transition). Each tab keeps its own natural height so
    /// opening Media stays compact instead of reserving System's tall layout.
    private var panelMinimumHeight: CGFloat {
        max(
            IslandExpandedLayout.minimumPanelHeight(for: transitionState.source),
            IslandExpandedLayout.minimumPanelHeight(for: transitionState.target)
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider().overlay(IslandTheme.mutedInk.opacity(0.18))
            panelStack
                .frame(maxWidth: .infinity,
                       minHeight: panelMinimumHeight,
                       alignment: .topLeading)
            tabBar
        }
        // The panel itself remains flush with the screen top; only its content
        // moves below the physical-notch area so the surface still covers the
        // title bar behind it.
        .padding(.top, IslandExpandedLayout.expandedTopClearance(notchHeight: 32))
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .foregroundStyle(IslandTheme.ink)
        .onChange(of: content) { updatedContent in
            synchronizePassiveContent(updatedContent)
        }
        .onChange(of: tabCoordinator.portalRequestID) { requestID in
            handlePortalRequest(requestID)
        }
        .onChange(of: tabCoordinator.portalCancellationID) { cancellationID in
            handlePortalCancellation(cancellationID)
        }
        .onChange(of: reduceMotion) { isReduced in
            guard isReduced else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                renderedPortalProgress = 0
                portalVisible = false
                portalTarget = nil
                portalDirection = .none
                portalAnimationToken = 0
            }
        }
    }

    private var header: some View {
        HStack {
            Text(title(for: tabCoordinator.headerContent))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                pinned ? viewModel.unpin() : viewModel.pin()
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .foregroundStyle(pinned ? IslandTheme.cobalt : IslandTheme.mutedInk)
            .help(pinned ? "Unpin" : "Pin island open")
            .accessibilityLabel(pinned ? "Unpin island" : "Pin island")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(IslandTheme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(IslandTheme.ink)
            .accessibilityLabel("Quit Notch Island")
        }
    }

    @ViewBuilder
    private func panel(for content: IslandContent) -> some View {
        switch content {
        case .media:
            if isTabEnabled(.media) {
                MediaPanel(vm: env.mediaPanelVM)
            } else {
                unavailablePanel(name: "Media", symbol: "play.circle")
            }
        case .systemStatus:
            if isTabEnabled(.systemStatus) {
                SystemPanel(vm: env.systemPanelVM)
            } else {
                unavailablePanel(
                    name: "System",
                    symbol: "gauge.with.dots.needle.bottom.50percent"
                )
            }
        case .finderShelf:
            if isTabEnabled(.finderShelf) {
                FinderShelfPanel(
                    vm: env.finderPanelVM,
                    onSearchFocusChanged: onKeyboardFocusChanged
                )
            } else {
                unavailablePanel(name: "Finder", symbol: "folder")
            }
        case .notification:
            placeholder(icon: "bell", text: viewModel.lastEvent?.payload.title ?? "Notification")
        }
    }

    private var panelStack: some View {
        ZStack(alignment: .topLeading) {
            if reduceMotion {
                panel(for: transitionState.target)
                    .id(IslandExpandedPanelLayer(content: transitionState.target).id)
                    .transition(.opacity)
            } else {
                ForEach(IslandExpandedTransition.layers(for: transitionState)) { layer in
                    transitionPanel(layer)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .compositingGroup()
        .clipped()
        .animation(
            reduceMotion
                ? .easeOut(duration: IslandMotion.reducedMotionFade)
                : nil,
            value: transitionState.target
        )
    }

    private func transitionPanel(_ layer: IslandExpandedPanelLayer) -> some View {
        let presentation = IslandExpandedTransition.presentation(
            for: layer.content,
            state: transitionState
        )
        let access = IslandExpandedTransition.access(
            for: layer.content,
            state: transitionState
        )
        return panel(for: layer.content)
            .offset(y: presentation.yOffset)
            .scaleEffect(presentation.scale, anchor: .top)
            .blur(radius: presentation.blur)
            .opacity(presentation.opacity)
            .allowsHitTesting(access.allowsHitTesting)
            .accessibilityHidden(access.accessibilityHidden)
            .animation(panelAnimation(for: layer), value: transitionState)
            .zIndex(layer.content == transitionState.target ? 1 : 0)
    }

    private func panelAnimation(for layer: IslandExpandedPanelLayer) -> Animation? {
        guard transitionActive else { return nil }
        if layer.content == transitionState.source {
            return .easeOut(duration: IslandMotion.tabOutgoingDuration)
        }
        if layer.content == transitionState.target {
            return .easeOut(duration: IslandMotion.tabIncomingDuration)
        }
        return nil
    }

    private func placeholder(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(IslandTheme.cobalt)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(IslandTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func unavailablePanel(name: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(IslandTheme.mutedInk)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(name) is disabled")
                    .font(.system(size: 12, weight: .semibold))
                Text("Enable it in Settings to use this panel.")
                    .font(.system(size: 11))
                    .foregroundStyle(IslandTheme.mutedInk)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) is disabled")
    }

    private var tabBar: some View {
        GeometryReader { proxy in
            let layout = TabRailLayoutModel.layout(
                availableWidth: proxy.size.width, reduceMotion: reduceMotion)
            let centres = railCentres(width: proxy.size.width, layout: layout)
            ZStack {
                HStack(spacing: layout.gap) {
                    ForEach(tabs, id: \.0) { tab in
                        tabCapsule(tab, layout: layout)
                    }
                }
                .frame(width: proxy.size.width, alignment: .center)

                portalDuplicate(centres: centres)
            }
            .frame(width: proxy.size.width,
                   height: IslandExpandedLayout.bottomRailHeight,
                   alignment: .center)
            .animation(
                layout.animates
                    ? .timingCurve(0.77, 0, 0.175, 1, duration: IslandMotion.tabIndicatorDuration)
                    : nil,
                value: transitionState.target
            )
        }
        .frame(height: IslandExpandedLayout.bottomRailHeight)
    }

    /// Active tab is a labelled capsule; inactive tabs are icon-only capsules.
    private func tabCapsule(
        _ tab: (IslandContent, String, String),
        layout: TabRailLayout
    ) -> some View {
        let selected = tab.0 == transitionState.target
        let enabled = isTabEnabled(tab.0)
        return Button {
            tabCoordinator.request(target: tab.0)
            viewModel.select(content: tab.0)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? IslandTheme.cobalt : IslandTheme.card)
                HStack(spacing: 6) {
                    Image(systemName: tab.2)
                    if selected && layout.showsActiveLabel {
                        Text(tab.1)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(width: selected ? layout.activeWidth : layout.inactiveWidth)
            .frame(height: IslandExpandedLayout.tabHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : IslandTheme.mutedInk)
        .opacity(enabled ? 1 : 0.42)
        .disabled(!enabled)
        .accessibilityLabel(tab.1)
        .accessibilityHint(enabled ? "" : "Enable this feature in Settings")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Centre X of each capsule for the current active target, so the portal
    /// accent travels with the active capsule instead of an equal-cell grid.
    private func railCentres(width: CGFloat, layout: TabRailLayout) -> [CGFloat] {
        let widths = tabs.map {
            $0.0 == transitionState.target ? layout.activeWidth : layout.inactiveWidth
        }
        let total = widths.reduce(0, +) + layout.gap * CGFloat(max(0, tabs.count - 1))
        var x = (width - total) / 2
        var centres: [CGFloat] = []
        for w in widths {
            centres.append(x + w / 2)
            x += w + layout.gap
        }
        return centres
    }

    @ViewBuilder
    private func portalDuplicate(centres: [CGFloat]) -> some View {
        if !reduceMotion,
           portalVisible,
           let portalTarget,
           let targetIndex = tabs.firstIndex(where: { $0.0 == portalTarget }),
           targetIndex < centres.count {
            let requestID = activePortalRequestID
            Image(systemName: symbol(for: portalTarget))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .position(x: centres[targetIndex],
                          y: IslandExpandedLayout.bottomRailHeight / 2)
                .modifier(OrbitalPortalEffect(
                    progress: renderedPortalProgress,
                    direction: portalDirection
                ))
                .modifier(PortalAnimationCompletionObserver(
                    observedValue: portalAnimationToken
                ) {
                    finishPortalAnimation(for: requestID)
                })
                .onAppear { startPortalAnimationIfNeeded() }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func synchronizePassiveContent(_ updatedContent: IslandContent) {
        guard transitionState.phase == .idle,
              transitionState.target != updatedContent else { return }
        let configuredReduceMotion = tabCoordinator.reduceMotion
        tabCoordinator.reduceMotion = true
        tabCoordinator.request(target: updatedContent)
        tabCoordinator.reduceMotion = configuredReduceMotion
    }

    private func isTabEnabled(_ content: IslandContent) -> Bool {
        IslandExpandedTabPolicy.isEnabled(
            content,
            availability: featureAvailability
        )
    }

    private func handlePortalRequest(_ requestID: UInt64) {
        guard !reduceMotion, requestID > 0 else { return }
        let target = tabCoordinator.state.target
        let direction = tabCoordinator.state.direction
        let mode = IslandPortalPresentationPolicy.requestMode(
            hasVisiblePresentation: portalVisible && portalAnimationToken > 0
        )
        activePortalRequestID = requestID

        switch mode {
        case .beginAtOrigin:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                renderedPortalProgress = 0
                portalTarget = target
                portalDirection = direction
                portalAnimationToken = 0
                portalVisible = true
            }
        case .retargetCurrentPresentation:
            withAnimation(.linear(duration: IslandMotion.tabPortalDuration)) {
                portalTarget = target
                portalDirection = direction
                renderedPortalProgress = 1
                portalAnimationToken += 1
            }
        }
    }

    private func startPortalAnimationIfNeeded() {
        guard portalVisible,
              portalAnimationToken == 0,
              activePortalRequestID == tabCoordinator.portalRequestID,
              !tabCoordinator.reduceMotion else { return }
        withAnimation(.linear(duration: IslandMotion.tabPortalDuration)) {
            renderedPortalProgress = 1
            portalAnimationToken = 1
        }
    }

    private func handlePortalCancellation(_ cancellationID: UInt64) {
        guard IslandPortalPresentationPolicy.shouldDismiss(
            cancellationRequestID: cancellationID,
            activePortalRequestID: activePortalRequestID,
            hasVisiblePresentation: portalVisible
        ) else { return }
        dismissPortalImmediately()
    }

    private func finishPortalAnimation(for requestID: UInt64) {
        guard portalVisible,
              activePortalRequestID == requestID else { return }
        dismissPortalImmediately()
    }

    private func dismissPortalImmediately() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            renderedPortalProgress = 0
            portalVisible = false
            portalTarget = nil
            portalDirection = .none
            portalAnimationToken = 0
        }
    }

    private func symbol(for content: IslandContent) -> String {
        switch content {
        case .media: return "play.circle"
        case .systemStatus: return "gauge.with.dots.needle.bottom.50percent"
        case .finderShelf: return "folder"
        case .notification: return "bell"
        }
    }

    private func title(for content: IslandContent) -> String {
        switch content {
        case .media: return "Media"
        case .systemStatus: return "System"
        case .finderShelf: return "Finder Shelf"
        case .notification: return "Notification"
        }
    }
}
