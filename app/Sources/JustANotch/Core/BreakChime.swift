import Foundation
import AVFoundation

/// Âm nhắc đứng dậy/uống nước: hai tiếng "bloop" giọt nước (sin trượt cao độ
/// lên nhanh) rồi một tiếng chuông nhỏ — khác hẳn arpeggio marimba của Learn để
/// nghe là biết loại nhắc nào. Tổng hợp một lần ra WAV rồi phát lại.
enum BreakChime {
    private static var player: AVAudioPlayer?

    private static var fileURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("break-chime-v1.wav")
    }

    static func play(volume: Float = 0.6) {
        if !FileManager.default.fileExists(atPath: fileURL.path) { try? render(to: fileURL) }
        guard let p = try? AVAudioPlayer(contentsOf: fileURL) else { return }
        p.volume = volume
        p.play()
        player = p
    }

    static func render(to url: URL) throws {
        let sr = 44_100.0
        let dur = 1.3
        let n = Int(sr * dur)
        var buf = [Float](repeating: 0, count: n)

        // Giọt nước: tần số trượt mũ f0 → f1 trong `glide` giây, tắt rất nhanh.
        func droplet(at start: Double, f0: Double, f1: Double, amp: Double) {
            let s0 = Int(start * sr)
            let glide = 0.07
            var phase = 0.0
            for i in 0..<min(Int(0.22 * sr), n - s0) {
                let t = Double(i) / sr
                let f = f0 * pow(f1 / f0, min(1, t / glide))
                phase += 2 * .pi * f / sr
                let env = min(1, t / 0.003) * exp(-t * 26)
                buf[s0 + i] += Float(amp * env * sin(phase))
            }
        }
        droplet(at: 0.00, f0: 520, f1: 1350, amp: 0.55)
        droplet(at: 0.15, f0: 720, f1: 1800, amp: 0.45)

        // Chuông nhỏ trong trẻo sau hai giọt.
        let bellStart = Int(0.30 * sr)
        for i in 0..<(n - bellStart) {
            let t = Double(i) / sr
            let env = min(1, t / 0.004) * exp(-t * 4.2)
            let v = sin(2 * .pi * 2093.0 * t) + 0.25 * sin(2 * .pi * 4186.0 * t) * exp(-t * 10)
            buf[bellStart + i] += Float(0.28 * env * v)
        }

        let peak = buf.map(abs).max() ?? 1
        let norm = 0.7 / max(peak, 0.0001)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        pcm.frameLength = AVAudioFrameCount(n)
        let ch = pcm.floatChannelData![0]
        for i in 0..<n {
            let tail = Float(min(1, Double(n - i) / (0.08 * sr)))
            ch[i] = buf[i] * norm * tail
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: pcm)
    }
}
