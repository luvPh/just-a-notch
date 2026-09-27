import Foundation
import AVFoundation

/// Âm báo Claude Code: "xong" = hai nốt ấm đi lên (E5 → A5), "chờ duyệt" = hai
/// tiếng blip ngắn cùng cao độ — khác Learn (arpeggio) và nhắc nghỉ (giọt nước).
enum ClaudeChime {
    enum Kind: String { case done, waiting }
    private static var player: AVAudioPlayer?

    private static func url(_ k: Kind) -> URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("claude-\(k.rawValue)-v1.wav")
    }

    static func play(_ k: Kind, volume: Float = 0.55) {
        let u = url(k)
        if !FileManager.default.fileExists(atPath: u.path) { try? render(k, to: u) }
        guard let p = try? AVAudioPlayer(contentsOf: u) else { return }
        p.volume = volume
        p.play()
        player = p
    }

    static func render(_ k: Kind, to url: URL) throws {
        let sr = 44_100.0
        let notes: [(f: Double, start: Double, decay: Double, amp: Double)] = k == .done
            ? [(659.25, 0.0, 5.0, 0.5), (880.0, 0.13, 4.0, 0.45)]
            : [(880.0, 0.0, 14.0, 0.45), (880.0, 0.16, 14.0, 0.45)]
        let dur = k == .done ? 1.2 : 0.6
        let n = Int(sr * dur)
        var buf = [Float](repeating: 0, count: n)
        for note in notes {
            let s0 = Int(note.start * sr)
            for i in 0..<(n - s0) {
                let t = Double(i) / sr
                let env = min(1, t / 0.006) * exp(-t * note.decay)
                let v = sin(2 * .pi * note.f * t) + 0.3 * sin(2 * .pi * note.f * 2 * t) * exp(-t * 6)
                buf[s0 + i] += Float(note.amp * env * v)
            }
        }
        let peak = buf.map(abs).max() ?? 1
        let norm = 0.65 / max(peak, 0.0001)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        pcm.frameLength = AVAudioFrameCount(n)
        let ch = pcm.floatChannelData![0]
        for i in 0..<n {
            let tail = Float(min(1, Double(n - i) / (0.06 * sr)))
            ch[i] = buf[i] * norm * tail
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: pcm)
    }
}
