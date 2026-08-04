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
    func seek(toFraction fraction: Double) {
        let f = min(1, max(0, fraction))
        runJS("if(v.duration){v.currentTime = \(f) * v.duration;}")
    }

    // MARK: - Playlist / queue

    /// Reads the watch page's playlist panel (or "up next" recommendations) via
    /// injected JS. Fields are joined with unit/record separators to survive the
    /// AppleScript round-trip. Empty if JS-from-Apple-Events is off or no list.
    func playlist() -> [MediaListItem] {
        let js = """
        (function(){var US=String.fromCharCode(31),RS=String.fromCharCode(30);
        var els=document.querySelectorAll('ytd-playlist-panel-video-renderer');
        if(!els.length)els=document.querySelectorAll('ytd-compact-video-renderer');
        var out=[];for(var i=0;i<els.length;i++){var el=els[i];
        var t=el.querySelector('#video-title');
        var title=t?((t.getAttribute('title')||t.textContent)||'').trim():'';
        var by=el.querySelector('#byline,#channel-name,.ytd-channel-name');
        var ch=by?by.textContent.trim():'';
        var du=el.querySelector('#text.ytd-thumbnail-overlay-time-status-renderer,.badge-shape-wiz__text,ytd-thumbnail-overlay-time-status-renderer #text');
        var dur=du?du.textContent.trim():'';
        var img=el.querySelector('img');var thumb=img?img.src:'';
        var a=el.querySelector('a#wc-endpoint,a#thumbnail,a');var href=a?a.href:'';
        var vid='';try{vid=new URL(href).searchParams.get('v')||'';}catch(e){}
        var sel=el.hasAttribute('selected')?'1':'0';
        out.push([vid,title,ch,dur,thumb,sel].join(US));}
        return out.join(RS);})();
        """
        guard let out = firstBrowserJS(js), !out.isEmpty else { return [] }
        let rs = Character(UnicodeScalar(30)), us = Character(UnicodeScalar(31))
        return out.split(separator: rs).enumerated().compactMap { idx, row -> MediaListItem? in
            let f = row.split(separator: us, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6, !f[1].isEmpty else { return nil }
            let vid = f[0]
            // Build the thumbnail from the video id — YouTube lazy-loads the panel's
            // <img>, so its src is usually a placeholder for off-screen rows.
            let thumb = vid.isEmpty ? (f[4].isEmpty ? nil : f[4])
                                    : "https://i.ytimg.com/vi/\(vid)/mqdefault.jpg"
            return MediaListItem(
                id: vid.isEmpty ? "\(idx)" : vid,
                index: idx,
                title: f[1],
                channel: f[2].isEmpty ? nil : f[2],
                duration: f[3].isEmpty ? nil : f[3],
                thumbnailURL: thumb,
                isCurrent: f[5] == "1")
        }
    }

    func play(item: MediaListItem) {
        let js = """
        (function(){var els=document.querySelectorAll('ytd-playlist-panel-video-renderer');
        if(!els.length)els=document.querySelectorAll('ytd-compact-video-renderer');
        var el=els[\(item.index)];if(el){var a=el.querySelector('a#wc-endpoint,a#thumbnail,a');
        if(a){a.click();return 'ok';}}return 'no';})();
        """
        _ = firstBrowserJS(js)
    }

    /// Runs `js` on the first running browser's YouTube watch tab, returning its result.
    private func firstBrowserJS(_ js: String) -> String? {
        for browser in runningBrowsers {
            if let out = runJSReading(js, browser: browser) { return out }
        }
        return nil
    }

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
