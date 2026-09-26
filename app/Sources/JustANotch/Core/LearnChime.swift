// app/Sources/JustANotch/Core/LearnChime.swift
import Foundation
import AVFoundation

/// Âm báo popup Learn: 3 nốt kiểu marimba/chuông gió (E6 → G#6 → B6), tổng hợp sẵn
/// ra WAV một lần rồi phát bằng AVAudioPlayer — nhẹ, trong, không chói.
enum LearnChime {
    private static var player: AVAudioPlayer?

    private static var fileURL: URL {
        LearnStore.defaultDir.appendingPathComponent("chime-v1.wav")
    }

    static func play(volume: Float = 0.6) {
        if !FileManager.default.fileExists(atPath: fileURL.path) { try? render(to: fileURL) }
        guard let p = try? AVAudioPlayer(contentsOf: fileURL) else { return }
        p.volume = volume
        p.play()
        player = p
    }

    /// Tổng hợp: mỗi nốt = sin cơ bản + bội 4 (màu marimba) + bội 2 nhẹ, attack 4ms,
    /// tắt dần mũ; nốt sau lệch 110ms, âm vang ngắn bằng 2 delay mờ.
    static func render(to url: URL) throws {
        let sr = 44_100.0
        let dur = 1.6
        let n = Int(sr * dur)
        var buf = [Float](repeating: 0, count: n)
        let notes: [(freq: Double, start: Double, amp: Double)] = [
            (1318.51, 0.00, 0.50),   // E6
            (1661.22, 0.11, 0.42),   // G#6
            (1975.53, 0.22, 0.38),   // B6
        ]
        for note in notes {
            let s0 = Int(note.start * sr)
            for i in 0..<(n - s0) {
                let t = Double(i) / sr
                let env = min(1, t / 0.004) * exp(-t * 5.5)
                let v = sin(2 * .pi * note.freq * t)
                    + 0.18 * sin(2 * .pi * note.freq * 2 * t) * exp(-t * 9)
                    + 0.10 * sin(2 * .pi * note.freq * 4 * t) * exp(-t * 18)
                buf[s0 + i] += Float(note.amp * env * v)
            }
        }
        // Vang ngắn.
        for (delay, gain) in [(0.083, 0.22), (0.151, 0.12)] {
            let d = Int(delay * sr)
            for i in stride(from: n - 1, through: d, by: -1) { buf[i] += buf[i - d] * Float(gain) }
        }
        let peak = buf.map(abs).max() ?? 1
        let norm = 0.7 / max(peak, 0.0001)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        pcm.frameLength = AVAudioFrameCount(n)
        let ch = pcm.floatChannelData![0]
        // Fade-out 80ms cuối tránh click.
        for i in 0..<n {
            let tail = Float(min(1, Double(n - i) / (0.08 * sr)))
            ch[i] = buf[i] * norm * tail
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: pcm)
    }
}
