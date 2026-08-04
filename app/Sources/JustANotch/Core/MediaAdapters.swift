// File: Sources/NotchIsland/Services/MediaAdapters.swift
import AppKit

/// A source-specific media adapter. Adapters must never crash and must report
/// `unsupported` when their app is not running or not scriptable.
protocol MediaAdapter: AnyObject {
    var appBundleID: String { get }
    var displayName: String { get }
    /// True when the backing app is currently running.
    var isRunning: Bool { get }
    func fetch() -> (track: MediaTrack?, state: PlaybackState)
    func playPause()
    func next()
    func previous()
    /// Seek to a 0...1 fraction of the current track. No-op if unsupported.
    func seek(toFraction fraction: Double)
}

extension MediaAdapter {
    func seek(toFraction fraction: Double) {}
}

/// Shared AppleScript execution helper. Returns nil on any error (including a
/// missing Automation permission) rather than throwing.
enum AppleScriptRunner {
    static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if errorInfo != nil { return nil }
        return result.stringValue
    }
}

// MARK: - Apple Music

final class AppleMusicAdapter: MediaAdapter {
    let appBundleID = "com.apple.Music"
    let displayName = "Music"

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == appBundleID }
    }

    func fetch() -> (track: MediaTrack?, state: PlaybackState) {
        guard isRunning else { return (nil, .unsupported) }
        let script = """
        tell application "Music"
            if it is running then
                set st to (player state as string)
                if st is "stopped" then return "stopped||||"
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set prog to 0
                try
                    set d to duration of current track
                    if d > 0 then set prog to (player position) / d
                end try
                return st & "|" & t & "|" & a & "|" & al & "|" & prog
            end if
        end tell
        """
        guard let out = AppleScriptRunner.run(script) else { return (nil, .unsupported) }
        return Self.parse(out, source: displayName)
    }

    func playPause() { _ = AppleScriptRunner.run("tell application \"Music\" to playpause") }
    func next() { _ = AppleScriptRunner.run("tell application \"Music\" to next track") }
    func previous() { _ = AppleScriptRunner.run("tell application \"Music\" to previous track") }
    func seek(toFraction fraction: Double) {
        let f = min(1, max(0, fraction))
        _ = AppleScriptRunner.run("tell application \"Music\" to set player position to ((duration of current track) * \(f))")
    }

    static func parse(_ out: String, source: String) -> (MediaTrack?, PlaybackState) {
        let parts = out.components(separatedBy: "|")
        let stateStr = parts.first ?? ""
        let state: PlaybackState = stateStr == "playing" ? .playing : (stateStr == "paused" ? .paused : .stopped)
        guard parts.count >= 4, !parts[1].isEmpty else { return (nil, state) }
        // Optional 5th field is a 0...1 progress fraction (AppleScript prints reals
        // with a "." or "," depending on locale — normalise before parsing).
        var progress: Double?
        if parts.count >= 5 {
            let raw = parts[4].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            if let p = Double(raw), p.isFinite { progress = min(1, max(0, p)) }
        }
        let track = MediaTrack(title: parts[1],
                               artist: parts[2].isEmpty ? nil : parts[2],
                               album: parts[3].isEmpty ? nil : parts[3],
                               sourceAppName: source,
                               progress: progress)
        return (track, state)
    }
}

// MARK: - Spotify

final class SpotifyAdapter: MediaAdapter {
    let appBundleID = "com.spotify.client"
    let displayName = "Spotify"

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == appBundleID }
    }

    func fetch() -> (track: MediaTrack?, state: PlaybackState) {
        guard isRunning else { return (nil, .unsupported) }
        let script = """
        tell application "Spotify"
            if it is running then
                set st to (player state as string)
                if st is "stopped" then return "stopped||||"
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set prog to 0
                try
                    set d to (duration of current track) / 1000
                    if d > 0 then set prog to (player position) / d
                end try
                return st & "|" & t & "|" & a & "|" & al & "|" & prog
            end if
        end tell
        """
        guard let out = AppleScriptRunner.run(script) else { return (nil, .unsupported) }
        return AppleMusicAdapter.parse(out, source: displayName)
    }

    func playPause() { _ = AppleScriptRunner.run("tell application \"Spotify\" to playpause") }
    func next() { _ = AppleScriptRunner.run("tell application \"Spotify\" to next track") }
    func previous() { _ = AppleScriptRunner.run("tell application \"Spotify\" to previous track") }
    func seek(toFraction fraction: Double) {
        let f = min(1, max(0, fraction))
        // Spotify duration is in milliseconds; player position is in seconds.
        _ = AppleScriptRunner.run("tell application \"Spotify\" to set player position to (((duration of current track) / 1000) * \(f))")
    }
}

// MARK: - Mock (previews & tests)

final class MockMediaAdapter: MediaAdapter {
    let appBundleID = "mock"
    let displayName = "Mock"
    var running = true
    var isRunning: Bool { running }
    private var playing = true

    func fetch() -> (track: MediaTrack?, state: PlaybackState) {
        guard running else { return (nil, .unsupported) }
        let track = MediaTrack(title: "Sample Song", artist: "Sample Artist",
                               album: "Demo", sourceAppName: displayName, progress: 0.4)
        return (track, playing ? .playing : .paused)
    }
    func playPause() { playing.toggle() }
    func next() {}
    func previous() {}
}
