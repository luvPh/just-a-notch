// File: Sources/NotchIsland/Island/PanelViewModels.swift
import Foundation
import Combine
import AppKit

/// Observable bridges from the Combine-based services to SwiftUI panels.

@MainActor
final class MediaPanelViewModel: ObservableObject {
    @Published var track: MediaTrack?
    @Published var state: PlaybackState = .unsupported
    private let service: MediaServiceProtocol
    private var cancellables: Set<AnyCancellable> = []

    init(service: MediaServiceProtocol) {
        self.service = service
        service.currentTrack.receive(on: RunLoop.main).sink { [weak self] in self?.track = $0 }.store(in: &cancellables)
        service.playbackState.receive(on: RunLoop.main).sink { [weak self] in self?.state = $0 }.store(in: &cancellables)
    }

    var compactPresentation: CompactIslandPresentation {
        CompactIslandPresentation.select(track: track)
    }

    func appear() { service.start(); service.refresh() }
    func disappear() {}
    func refresh() { service.refresh() }
    func playPause() { service.playPause() }
    func next() { service.nextTrack() }
    func previous() { service.previousTrack() }
}

@MainActor
final class SystemPanelViewModel: ObservableObject {
    @Published var snapshot: SystemSnapshot = .empty
    private let service: SystemMonitorServiceProtocol
    private var cancellables: Set<AnyCancellable> = []

    init(service: SystemMonitorServiceProtocol) {
        self.service = service
        service.snapshot.receive(on: RunLoop.main).sink { [weak self] in self?.snapshot = $0 }.store(in: &cancellables)
    }

    func appear() { service.setActive(true); service.start(); service.refresh() }
    func disappear() { service.setActive(false) }
}

@MainActor
final class FinderPanelViewModel: ObservableObject {
    @Published var items: [FinderShelfItem] = []
    @Published var query: String = ""
    private let service: FinderServiceProtocol
    private var cancellables: Set<AnyCancellable> = []

    init(service: FinderServiceProtocol) {
        self.service = service
        service.items.receive(on: RunLoop.main).sink { [weak self] in self?.items = $0 }.store(in: &cancellables)
    }

    var filtered: [FinderShelfItem] {
        query.isEmpty ? items : items.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    func open(_ item: FinderShelfItem) { service.open(item: item) }
    func reveal(_ item: FinderShelfItem) { service.revealInFinder(item: item) }
    func copyPath(_ item: FinderShelfItem) { service.copyPath(item: item) }
    func remove(_ item: FinderShelfItem) { service.removeItem(id: item.id) }
    func add(url: URL) { service.addItem(url: url) }
    func isAvailable(_ item: FinderShelfItem) -> Bool { service.resolveURL(for: item) != nil }

    /// Present an open panel to pin a new location.
    func addViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin"
        if panel.runModal() == .OK {
            panel.urls.forEach { service.addItem(url: $0) }
        }
    }
}
