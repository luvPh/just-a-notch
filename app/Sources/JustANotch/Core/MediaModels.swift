// File: Sources/NotchIsland/Core/Models/MediaModels.swift
import Foundation

enum PlaybackState: Equatable {
    case stopped
    case playing
    case paused
    case unsupported   // no scriptable player running / not controllable

    var isPlaying: Bool { self == .playing }
}

struct MediaTrack: Equatable {
    var title: String
    var artist: String?
    var album: String?
    var sourceAppName: String
    /// Progress 0...1 when known.
    var progress: Double?
    /// Artwork bytes when the source provides them (kept small; not cached to disk).
    var artworkData: Data?

    init(title: String, artist: String? = nil, album: String? = nil,
         sourceAppName: String, progress: Double? = nil, artworkData: Data? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.sourceAppName = sourceAppName
        self.progress = progress
        self.artworkData = artworkData
    }
}
