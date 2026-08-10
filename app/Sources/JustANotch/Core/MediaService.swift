// File: Sources/NotchIsland/Services/MediaService.swift
import Foundation
import Combine
import AppKit

struct MediaAvailabilityDebouncer {
    private(set) var stableTrack: MediaTrack?
    private var consecutiveMissing = 0

    mutating func accept(_ candidate: MediaTrack?) -> MediaTrack? {
        if let candidate {
            stableTrack = candidate
            consecutiveMissing = 0
            return candidate
        }
        consecutiveMissing += 1
        // Tolerate a few transient misses (a slow/failed AppleScript read) so the
        // notch doesn't blink back to empty between polls.
        if consecutiveMissing < 4 { return stableTrack }
        stableTrack = nil
        return nil
    }
}

/// Coordinates media adapters, preferring whichever supported player is
/// actively playing. Polls only while started (i.e. while the media feature is
/// visible/enabled) to keep idle CPU near zero.
final class MediaService: MediaServiceProtocol {
    let currentTrack = CurrentValueSubject<MediaTrack?, Never>(nil)
    let playbackState = CurrentValueSubject<PlaybackState, Never>(.unsupported)

    private let adapters: [MediaAdapter]
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.notchisland.media", qos: .utility)
    private var availabilityDebouncer = MediaAvailabilityDebouncer()

    /// The adapter last observed as active; used to route control commands.
    private var activeAdapter: MediaAdapter?

    var hasAvailableSource: Bool {
        adapters.contains { $0.isRunning }
    }

    init(adapters: [MediaAdapter] = [AppleMusicAdapter(), SpotifyAdapter(), YouTubeBrowserAdapter()]) {
        self.adapters = adapters
    }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() { queue.async { [weak self] in self?.poll() } }

    private func poll() {
        let chosen = Self.selectActiveAdapter(from: adapters)

        if let chosen {
            activeAdapter = chosen.adapter
            currentTrack.send(availabilityDebouncer.accept(chosen.track))
            playbackState.send(chosen.state)
        } else {
            activeAdapter = nil
            currentTrack.send(availabilityDebouncer.accept(nil))
            playbackState.send(.unsupported)
        }
    }

    /// Chooses a playing source first, then a running source in its reported
    /// state. Keeping this deterministic avoids showing a fake playing track
    /// when a player is open but stopped or not yet authorized.
    static func selectActiveAdapter(from adapters: [MediaAdapter]) ->
        (adapter: MediaAdapter, track: MediaTrack?, state: PlaybackState)? {
        // Prefer a playing adapter; fall back to the first running one.
        var chosen: (adapter: MediaAdapter, track: MediaTrack?, state: PlaybackState)?
        for adapter in adapters where adapter.isRunning {
            let result = adapter.fetch()
            if result.state == .playing {
                chosen = (adapter, result.track, result.state)
                break
            }
            if chosen == nil { chosen = (adapter, result.track, result.state) }
        }
        return chosen
    }

    func playPause() { activeAdapter?.playPause(); refresh() }
    func nextTrack() { activeAdapter?.next(); refresh() }
    func previousTrack() { activeAdapter?.previous(); refresh() }
    func seek(toFraction fraction: Double) { activeAdapter?.seek(toFraction: fraction); refresh() }

    func fetchPlaylist(_ completion: @escaping ([MediaListItem]) -> Void) {
        queue.async { [weak self] in
            let items = self?.activeAdapter?.playlist() ?? []
            DispatchQueue.main.async { completion(items) }
        }
    }

    func play(item: MediaListItem) {
        queue.async { [weak self] in
            self?.activeAdapter?.play(item: item)
            self?.poll()
        }
    }

    func focusSource() {
        queue.async { [weak self] in self?.activeAdapter?.focusSource() }
    }
}
