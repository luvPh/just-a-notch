// File: Sources/NotchIsland/Services/YouTubeBrowserAdapter.swift
import AppKit
import os

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
                let st = playbackStatus(browser: browser)
                var track = MediaTrack(title: clean.isEmpty ? "YouTube" : clean,
                                       artist: st.channel,
                                       sourceAppName: browserName(browser),
                                       sourceBundleID: browser,
                                       progress: st.progress,
                                       artworkData: st.videoID.flatMap(Self.thumbnail),
                                       volume: st.volume)
                track.duration = st.duration
                let state = st.state
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
    /// Sets the tab's own <video> volume. Unmutes on any non-zero value so the
    /// slider isn't silently overridden by a muted player.
    func setVolume(_ volume: Double) {
        let v = min(1, max(0, volume))
        runJS("v.volume = \(v); v.muted = \(v <= 0 ? "true" : "false");")
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

    /// Bring the YouTube tab to the front: select it inside its window, raise
    /// that window, and activate the browser.
    func focusSource() {
        // If YouTube is installed as a standalone app (a Chrome PWA lives at
        // ~/Applications/Chrome Apps.localized/YouTube.app with a
        // "com.google.Chrome.app.*" bundle id, or a real native app), prefer it.
        if let ytApp = NSWorkspace.shared.runningApplications.first(where: { app in
            (app.localizedName ?? "").localizedCaseInsensitiveContains("youtube")
        }) {
            ytApp.unhide()
            ytApp.activate(options: [.activateAllWindows])
            return
        }

        for browser in runningBrowsers {
            let script: String
            if browser == chromeID {
                script = """
                tell application "Google Chrome"
                    repeat with w in windows
                        set i to 0
                        repeat with t in tabs of w
                            set i to i + 1
                            set u to URL of t
                            if (u contains "youtube.com/watch") or (u contains "youtube.com/shorts/") or (u contains "youtube.com/live/") or (u contains "youtu.be/") then
                                set active tab index of w to i
                                set index of w to 1
                                activate
                                return "ok"
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
                                set current tab of w to t
                                set index of w to 1
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end tell
                return ""
                """
            }
            if AppleScriptRunner.run(script) == "ok" {
                // AppleScript `activate` is unreliable from a background agent app;
                // nudge the browser forward explicitly too.
                NSWorkspace.shared.runningApplications
                    .first { $0.bundleIdentifier == browser }?
                    .activate(options: [.activateAllWindows])
                return
            }
        }
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

    /// Reads `video.paused`, `currentTime/duration` and the tab's volume via
    /// injected JS in one call. Returns nils if JS-from-Apple-Events is disabled
    /// or no video is found.
    private struct Status {
        var state: PlaybackState?, progress: Double?, volume: Double?
        var duration: Double?, videoID: String?, channel: String?
    }

    private func playbackStatus(browser: String) -> Status {
        // trạng thái | tiến độ | âm lượng | thời lượng | mã video | tên kênh
        let js = """
        var v=document.querySelector('video'); \
        var pp=location.pathname.split('/'); var id=new URLSearchParams(location.search).get('v')||((pp[1]=='shorts'||pp[1]=='live')?pp[2]:'')||''; \
        var ch=document.querySelector('#owner ytd-channel-name a, ytd-video-owner-renderer #channel-name a, #channel-name a'); \
        v ? ((v.paused ? 'paused' : 'playing') + '|' + \
        (v.duration > 0 ? (v.currentTime / v.duration) : 0) + '|' + \
        (v.muted ? 0 : v.volume) + '|' + (isFinite(v.duration) ? v.duration : 0) + '|' + id + '|' + \
        (ch ? ch.textContent.trim().split('|').join(' ') : '')) : 'none';
        """
        guard let out = runJSReading(js, browser: browser) else { return Status() }
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
        var volume: Double?
        if parts.count >= 3, let v = Double(parts[2].trimmingCharacters(in: .whitespaces)), v.isFinite {
            volume = min(1, max(0, v))
        }
        var st = Status(state: state, progress: progress, volume: volume)
        if parts.count >= 4, let d = Double(parts[3].trimmingCharacters(in: .whitespaces)), d.isFinite, d > 0 {
            st.duration = d
        }
        if parts.count >= 5 { let id = parts[4].trimmingCharacters(in: .whitespaces); st.videoID = id.isEmpty ? nil : id }
        if parts.count >= 6 { let c = parts[5].trimmingCharacters(in: .whitespaces); st.channel = c.isEmpty ? nil : c }
        return st
    }

    /// Thumbnail 16:9 của video (cache theo mã; tải đồng bộ trên luồng poll, ~10KB).
    private static var thumbCache: [String: Data] = [:]
    private static let thumbLock = NSLock()
    private static func thumbnail(_ id: String) -> Data? {
        thumbLock.lock(); if let d = thumbCache[id] { thumbLock.unlock(); return d }; thumbLock.unlock()
        guard let url = URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"),
              let d = try? Data(contentsOf: url), !d.isEmpty else { return nil }
        thumbLock.lock(); thumbCache[id] = d; thumbLock.unlock()
        return d
    }

    /// Lệnh ĐIỀU KHIỂN gửi vào tab (play/pause, volume, next…) — ghi log để truy vết
    /// khi nhạc bị dừng/tắt tiếng bất ngờ: `log show --predicate 'subsystem == "com.justanotch.app"'`.
    private static let log = Logger(subsystem: "com.justanotch.app", category: "youtube")

    private func runJS(_ body: String) {
        Self.log.notice("control → \(body, privacy: .public)")
        for browser in runningBrowsers { _ = runJSReading("var v=document.querySelector('video'); if(v){\(body)} 'ok';", browser: browser) }
    }

    @discardableResult
    private func runJSReading(_ js: String, browser: String) -> String? {
        // AppleScript: escape \ trước rồi tới " (dấu \ trong JS sẽ làm hỏng cả script).
        let escaped = js.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
