// File: Sources/NotchIsland/Services/YouTubeBrowserAdapter.swift
import AppKit

/// Best-effort "now playing" for YouTube running in Safari or Google Chrome.
///
/// Capabilities & limits (all via public scripting / Automation):
/// - Display: reads the title of a supported YouTube watch, Shorts, live, or
///   youtu.be tab once Automation permission is granted.
/// - Control (play/pause): injects JavaScript into that tab. This ONLY works if
///   the user has enabled "Allow JavaScript from Apple Events" in the browser's
///   Develop menu; otherwise controls silently no-op.
/// - Artwork / precise progress / next-video are not exposed → omitted.
final class YouTubeBrowserAdapter: MediaAdapter {
    let appBundleID = "youtube.browser"
    let displayName = "YouTube"

    private let chromeID = "com.google.Chrome"
    private let safariID = "com.apple.Safari"

    private var runningBrowsers: [String] {
        NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
            .filter { $0 == chromeID || $0 == safariID }
    }

    var isRunning: Bool { !runningBrowsers.isEmpty }

    func fetch() -> (track: MediaTrack?, state: PlaybackState) {
        for browser in runningBrowsers {
            if let title = tabTitle(browser: browser) {
                let clean = title
                    .replacingOccurrences(of: " - YouTube", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let (state, progress) = playbackStatus(browser: browser)
                let track = MediaTrack(title: clean.isEmpty ? "YouTube" : clean,
                                       artist: nil,
                                       sourceAppName: browserName(browser),
                                       progress: progress)
                return (track, state ?? .playing)
            }
        }
        return (nil, .unsupported)
    }

    func playPause() { runJS("v.paused ? v.play() : v.pause();") }
    func next() { runJS("document.querySelector('.ytp-next-button')?.click();") }
    func previous() { runJS("window.history.back();") }

    // MARK: - Scripting

    private func browserName(_ bundleID: String) -> String {
        bundleID == chromeID ? "YouTube · Chrome" : "YouTube · Safari"
    }

    static func isSupportedVideoURL(_ url: String) -> Bool {
        let url = url.lowercased()
        return url.contains("youtube.com/watch")
            || url.contains("youtube.com/shorts/")
            || url.contains("youtube.com/live/")
            || url.contains("youtu.be/")
    }

    private func tabTitle(browser: String) -> String? {
        let script: String
        if browser == chromeID {
            script = """
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if (u contains "youtube.com/watch") or (u contains "youtube.com/shorts/") or (u contains "youtube.com/live/") or (u contains "youtu.be/") then
                            return u & (ASCII character 31) & (title of t)
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
        } else {
            script = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if (u contains "youtube.com/watch") or (u contains "youtube.com/shorts/") or (u contains "youtube.com/live/") or (u contains "youtu.be/") then
                            return u & (ASCII character 31) & (name of t)
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
        }
        guard let out = AppleScriptRunner.run(script),
              let separator = out.firstIndex(of: Character(UnicodeScalar(31))) else { return nil }
        let url = String(out[..<separator])
        let title = String(out[out.index(after: separator)...])
        guard Self.isSupportedVideoURL(url), !title.isEmpty else { return nil }
        return title
    }

    /// Reads `video.paused` and `currentTime/duration` via injected JS in one call.
    /// Returns (nil, nil) if JS-from-Apple-Events is disabled or no video is found.
    private func playbackStatus(browser: String) -> (state: PlaybackState?, progress: Double?) {
        let js = """
        var v=document.querySelector('video'); \
        v ? ((v.paused ? 'paused' : 'playing') + '|' + \
        (v.duration > 0 ? (v.currentTime / v.duration) : 0)) : 'none';
        """
        guard let out = runJSReading(js, browser: browser) else { return (nil, nil) }
        let parts = out.components(separatedBy: "|")
        let state: PlaybackState?
        switch parts.first {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = nil
        }
        var progress: Double?
        if parts.count >= 2, let p = Double(parts[1].trimmingCharacters(in: .whitespaces)), p.isFinite {
            progress = min(1, max(0, p))
        }
        return (state, progress)
    }

    private func runJS(_ body: String) {
        for browser in runningBrowsers { _ = runJSReading("var v=document.querySelector('video'); if(v){\(body)} 'ok';", browser: browser) }
    }

    @discardableResult
    private func runJSReading(_ js: String, browser: String) -> String? {
        let escaped = js.replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        if browser == chromeID {
            script = """
            tell application "Google Chrome"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t) contains "youtube.com/watch" then
                            return (execute t javascript "\(escaped)")
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
        } else {
            script = """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t) contains "youtube.com/watch" then
                            return (do JavaScript "\(escaped)" in t)
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
        }
        let out = AppleScriptRunner.run(script)
        return (out?.isEmpty == false) ? out : nil
    }
}
