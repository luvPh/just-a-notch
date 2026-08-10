import Foundation
import Combine

/// Media source lifecycle + control, reused from the original project.
protocol MediaServiceProtocol: AnyObject {
    var currentTrack: CurrentValueSubject<MediaTrack?, Never> { get }
    var playbackState: CurrentValueSubject<PlaybackState, Never> { get }
    var hasAvailableSource: Bool { get }
    func playPause()
    func nextTrack()
    func previousTrack()
    func seek(toFraction fraction: Double)
    /// Fetch the active source's queue/playlist off the main thread.
    func fetchPlaylist(_ completion: @escaping ([MediaListItem]) -> Void)
    /// Switch playback to a queue entry.
    func play(item: MediaListItem)
    /// Bring the active source's window/tab to the front.
    func focusSource()
    func refresh()
    func start()
    func stop()
}
