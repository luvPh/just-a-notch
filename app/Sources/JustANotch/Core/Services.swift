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
    func refresh()
    func start()
    func stop()
}
