// File: Sources/NotchIsland/Core/Protocols/Services.swift
import Foundation
import Combine

/// Lifecycle common to services that observe the system. Services are only
/// started when their feature is enabled, and stopped to keep idle CPU low.
protocol LifecycleService: AnyObject {
    func start()
    func stop()
    func refresh()
}

// MARK: - Finder

protocol FinderServiceProtocol: AnyObject {
    var items: CurrentValueSubject<[FinderShelfItem], Never> { get }
    func addItem(url: URL)
    func removeItem(id: UUID)
    /// Resolve the on-disk URL for an item, refreshing a stale bookmark. Returns
    /// nil if the target is gone.
    func resolveURL(for item: FinderShelfItem) -> URL?
    func open(item: FinderShelfItem)
    func revealInFinder(item: FinderShelfItem)
    func copyPath(item: FinderShelfItem)
}

// MARK: - System monitor

protocol SystemMonitorServiceProtocol: LifecycleService {
    var snapshot: CurrentValueSubject<SystemSnapshot, Never> { get }
    /// Lower the polling frequency when the island is not visible.
    func setActive(_ active: Bool)
}

// MARK: - Media

protocol MediaServiceProtocol: AnyObject {
    var currentTrack: CurrentValueSubject<MediaTrack?, Never> { get }
    var playbackState: CurrentValueSubject<PlaybackState, Never> { get }
    var hasAvailableSource: Bool { get }
    func playPause()
    func nextTrack()
    func previousTrack()
    func refresh()
    func start()
    func stop()
}
