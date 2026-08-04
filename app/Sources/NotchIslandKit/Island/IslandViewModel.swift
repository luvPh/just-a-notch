// File: Sources/NotchIsland/Island/IslandViewModel.swift
import Foundation
import Combine
import SwiftUI

/// Bridges the pure `IslandStateMachine` to SwiftUI, owning the hover-delay and
/// auto-collapse timers. All mutation goes through the machine so behaviour
/// stays deterministic and testable.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var state: IslandPresentationState = .compact
    @Published private(set) var lastEvent: IslandEvent?

    private var machine = IslandStateMachine()
    private let settings: SettingsStore

    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private func apply(_ input: IslandInput) {
        let new = machine.handle(input)
        if new != state {
            state = new
            scheduleAutoCollapseIfNeeded()
        }
    }

    // MARK: - Interaction entry points

    func hoverBegan() {
        guard settings.openOnHover else { return }
        hoverTask?.cancel()
        let delay = settings.hoverDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            self?.apply(.hoverBegan)
        }
    }

    func hoverEnded() {
        hoverTask?.cancel()
        apply(.hoverEnded)
    }

    func clicked(_ content: IslandContent = .systemStatus) {
        hoverTask?.cancel()
        apply(.clicked(content))
    }

    func dismiss() { apply(.dismiss) }
    func pin() { apply(.pin) }
    func unpin() { apply(.unpin) }
    func beginEditing() { apply(.beginEditing) }
    func endEditing() { apply(.endEditing) }

    func select(content: IslandContent) {
        apply(.clicked(content))
    }

    // MARK: - Events

    func post(_ event: IslandEvent) {
        lastEvent = event
        apply(.event(event))
        guard machine.activeTransientEventID == event.id, let duration = event.duration else { return }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            self?.apply(.eventExpired(event.id))
        }
    }

    // MARK: - Auto-collapse

    private func scheduleAutoCollapseIfNeeded() {
        collapseTask?.cancel()
        guard case .expanded = state else { return }
        let timeout = settings.autoCollapseTimeout
        guard timeout > 0 else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if Task.isCancelled { return }
            self?.apply(.autoCollapse)
        }
    }
}
