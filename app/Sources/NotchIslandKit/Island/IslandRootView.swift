// File: Sources/NotchIsland/Island/IslandRootView.swift
import SwiftUI

enum IslandRootSizing {
    static func compactWidth(coreWidth: CGFloat?, hasMedia: Bool) -> CGFloat {
        CompactGeometryModel.layout(
            coreWidth: coreWidth,
            state: hasMedia ? .active : .quiet
        ).surfaceWidth
    }
}

struct IslandRootLayers: Equatable {
    let compact: Bool
    let expanded: Bool
}

struct IslandCompactLayerPresentation: Equatable {
    let visible: Bool
    let activeMotion: Bool
    let allowsHitTesting: Bool
    let accessibilityHidden: Bool
}

enum IslandCompactLayerPolicy {
    static func presentation(
        for phase: IslandMotionPhase
    ) -> IslandCompactLayerPresentation {
        switch phase {
        case .resting:
            return IslandCompactLayerPresentation(
                visible: true,
                activeMotion: true,
                allowsHitTesting: true,
                accessibilityHidden: false
            )
        case .expanding:
            return IslandCompactLayerPresentation(
                visible: true,
                activeMotion: true,
                allowsHitTesting: false,
                accessibilityHidden: true
            )
        case .settled, .anticipatingClose:
            return IslandCompactLayerPresentation(
                visible: false,
                activeMotion: false,
                allowsHitTesting: false,
                accessibilityHidden: true
            )
        case .collapsing:
            return IslandCompactLayerPresentation(
                visible: true,
                activeMotion: true,
                allowsHitTesting: false,
                accessibilityHidden: true
            )
        }
    }
}

enum IslandRootComposition {
    static func layers(for phase: IslandMotionPhase) -> IslandRootLayers {
        switch phase {
        case .resting:
            return IslandRootLayers(compact: true, expanded: false)
        case .expanding, .anticipatingClose, .collapsing:
            return IslandRootLayers(compact: true, expanded: true)
        case .settled:
            return IslandRootLayers(compact: true, expanded: true)
        }
    }
}

/// Root island view. Renders compact vs expanded based on the view model state,
/// and reports its desired size so the panel controller can resize the window.
struct IslandRootView: View {
    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var mediaViewModel: MediaPanelViewModel
    @ObservedObject var motionCoordinator: IslandMotionCoordinator
    @ObservedObject var tabCoordinator: TabTransitionCoordinator
    let env: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Reports the view's preferred size to the hosting controller.
    var onSizeChange: (CGSize, Bool) -> Void
    var onKeyboardFocusChanged: (Bool) -> Void
    var onReduceMotionChanged: (Bool) -> Void

    private var expanded: Bool { viewModel.state.isExpandedLike }
    private var contentMode: IslandContent {
        viewModel.state.content ?? tabCoordinator.state.target
    }

    private var layers: IslandRootLayers {
        IslandRootComposition.layers(for: motionCoordinator.phase)
    }

    private var compactPresentation: IslandCompactLayerPresentation {
        IslandCompactLayerPolicy.presentation(for: motionCoordinator.phase)
    }

    private var motionReduced: Bool {
        reduceMotion || settings.reduceAnimation
    }

    /// Right-shift of the surface inside the fixed envelope so the physical core
    /// stays stationary as the left wing opens/closes.
    private var compactRevealOffset: CGFloat {
        motionCoordinator.compactEnvelopeGeometry.leftReveal
            - motionCoordinator.asymmetricGeometry.leftReveal
    }

    var body: some View {
        ZStack(alignment: .top) {
            if layers.compact {
                IslandCompactView(
                    height: settings.compactHeight,
                    geometry: motionCoordinator.asymmetricGeometry,
                    reading: motionCoordinator.readingState.presentationState == .mediaReading,
                    cornerRadius: settings.cornerRadius,
                    event: viewModel.state == .compact ? nil : viewModel.lastEvent,
                    track: mediaViewModel.track,
                    playbackState: mediaViewModel.state,
                    phase: motionCoordinator.phase,
                    reduceMotion: motionReduced,
                    activeMotion: compactPresentation.activeMotion,
                    onPlayPause: { mediaViewModel.playPause() }
                )
                // Anchor the surface within the fixed envelope so the core stays
                // put; the left wing width + this offset animate together in
                // SwiftUI (window never resizes) for a smooth reveal.
                .offset(x: compactRevealOffset)
                .frame(width: motionCoordinator.compactEnvelopeGeometry.totalWidth,
                       alignment: .leading)
                .animation(
                    motionReduced
                        ? nil
                        : .spring(response: 0.34, dampingFraction: 0.9),
                    value: motionCoordinator.asymmetricGeometry
                )
                .opacity(compactPresentation.visible ? 1 : 0)
                .zIndex(
                    motionCoordinator.phase == .anticipatingClose
                        || motionCoordinator.phase == .collapsing ? 2 : 0
                )
                .allowsHitTesting(compactPresentation.allowsHitTesting)
                .accessibilityHidden(compactPresentation.accessibilityHidden)
            }

            if layers.expanded {
                ZStack {
                    IslandExpandedView(
                        viewModel: viewModel,
                        tabCoordinator: tabCoordinator,
                        env: env,
                        content: contentMode,
                        pinned: { if case .pinned = viewModel.state { return true } else { return false } }(),
                        reduceMotion: motionReduced,
                        onKeyboardFocusChanged: onKeyboardFocusChanged
                    )
                    .frame(width: settings.expandedWidth)

                    LinearGradient(
                        colors: [.black, Color(red: 0.06, green: 0.07, blue: 0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(NotchShape(bottomRadius: settings.cornerRadius))
                    .allowsHitTesting(false)
                    .zIndex(-1)
                }
                .opacity(motionCoordinator.phase == .collapsing ? 0 : 1)
                .animation(
                    motionReduced
                        ? .easeOut(duration: IslandMotion.reducedMotionFade)
                        : .easeOut(duration: IslandMotion.collapseDuration),
                    value: motionCoordinator.phase
                )
                .zIndex(1)
                .allowsHitTesting(expanded && motionCoordinator.phase != .collapsing)
            }
        }
        .clipShape(NotchShape(bottomRadius: settings.cornerRadius))
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onSizeChange(proxy.size, layers.expanded) }
                    .onChange(of: proxy.size) { onSizeChange($0, layers.expanded) }
                    .onChange(of: layers.expanded) { includesExpanded in
                        onSizeChange(proxy.size, includesExpanded)
                    }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hovering ? viewModel.hoverBegan() : viewModel.hoverEnded()
        }
        .onTapGesture {
            if !expanded {
                viewModel.clicked(IslandDefaultContent.select(
                    mediaAvailable: mediaViewModel.track != nil
                ))
            }
        }
        .accessibilityAddTraits(.isButton)
        .onAppear { onReduceMotionChanged(motionReduced) }
        .onChange(of: motionReduced) { onReduceMotionChanged($0) }
    }
}
