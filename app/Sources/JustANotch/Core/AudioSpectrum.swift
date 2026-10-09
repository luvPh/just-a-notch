import Foundation
import CoreAudio
import AudioToolbox
import Accelerate

/// Phổ âm thanh hệ thống THẬT cho sóng nhạc: Core Audio process tap (macOS 14.2+)
/// nghe toàn bộ âm ra loa → FFT → vài dải tần (log). Cần quyền
/// "System Audio Recording" (hỏi 1 lần). Lỗi / chưa cấp quyền → `levels` trả nil,
/// sóng tự quay về kiểu giả lập.
final class AudioSpectrum {
    static let shared = AudioSpectrum()

    static let bandCount = 7
    private let fftSize = 1024

    private var users = 0
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "notch.audio.spectrum")

    private let lock = NSLock()
    private var bands = [Float](repeating: 0, count: AudioSpectrum.bandCount)
    private var lastUpdate: CFAbsoluteTime = 0
    private var sampleRate: Double = 48_000

    // Chỉ chạm trong IOProc (luồng audio).
    private var ring = [Float]()
    private var fft: vDSP.FFT<DSPSplitComplex>?
    private var window = [Float]()

    /// Mức 0…1 của từng dải; nil nếu không có dữ liệu mới (chưa cấp quyền, tap lỗi).
    var levels: [Float]? {
        lock.lock(); defer { lock.unlock() }
        guard CFAbsoluteTimeGetCurrent() - lastUpdate < 0.4 else { return nil }
        return bands
    }

    func acquire() {
        queue.async {
            self.users += 1
            if self.users == 1 { self.start() }
        }
    }

    func release() {
        queue.async {
            self.users = max(0, self.users - 1)
            if self.users == 0 { self.stop() }
        }
    }

    // MARK: - Tap lifecycle

    private func start() {
        guard #available(macOS 14.2, *) else { return }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr else { return }
        tapID = tap

        // Định dạng của tap (lấy sample rate).
        var fmt = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &fmt) == noErr, fmt.mSampleRate > 0 {
            sampleRate = fmt.mSampleRate
        }

        var dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "JustANotchSpectrum",
            kAudioAggregateDeviceUIDKey: "com.justanotch.spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        if let out = defaultOutputUID() {
            dict[kAudioAggregateDeviceMainSubDeviceKey] = out
            dict[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: out]]
        }
        var agg = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agg) == noErr else { stop(); return }
        aggID = agg

        let n = fftSize
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(n))), radix: .radix2, ofType: DSPSplitComplex.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        ring = []

        var pid: AudioDeviceIOProcID?
        let st = AudioDeviceCreateIOProcIDWithBlock(&pid, agg, nil) { [weak self] _, input, _, _, _ in
            self?.consume(input)
        }
        guard st == noErr, let pid else { stop(); return }
        procID = pid
        if AudioDeviceStart(agg, pid) != noErr { stop() }
    }

    private func stop() {
        if aggID != kAudioObjectUnknown {
            if let p = procID { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p) }
            AudioHardwareDestroyAggregateDevice(aggID)
        }
        procID = nil
        aggID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func defaultOutputUID() -> String? {
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr
        else { return nil }
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        let st = withUnsafeMutablePointer(to: &uid) { AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, $0) }
        return st == noErr ? uid as String : nil
    }

    // MARK: - Analysis (luồng audio)

    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = abl.first, let raw = first.mData else { return }
        let ch = Int(max(1, first.mNumberChannels))
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * ch)
        let p = raw.assumingMemoryBound(to: Float.self)
        // Interleaved → trộn mono; deinterleaved → cộng thêm buffer thứ 2 nếu có.
        let second = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil
        for i in 0..<frames {
            var s = p[i * ch]
            if ch > 1 { s = (s + p[i * ch + 1]) * 0.5 } else if let q = second { s = (s + q[i]) * 0.5 }
            ring.append(s)
        }
        if ring.count > fftSize * 2 { ring.removeFirst(ring.count - fftSize) }
        guard ring.count >= fftSize else { return }
        analyze(Array(ring.suffix(fftSize)))
        ring.removeFirst(min(ring.count, fftSize / 2))   // chồng 50%
    }

    private func analyze(_ samples: [Float]) {
        guard let fft else { return }
        let n = fftSize, half = n / 2
        let windowed = vDSP.multiply(samples, window)
        var real = [Float](repeating: 0, count: half), imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { wb in
                    vDSP_ctoz(wb.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                fft.forward(input: split, output: &split)
                vDSP.absolute(split, result: &mags)
            }
        }

        // Dải log 50Hz … 12kHz.
        let lo = 50.0, hi = min(12_000.0, sampleRate / 2)
        let binHz = sampleRate / Double(n)
        var out = [Float](repeating: 0, count: Self.bandCount)
        for b in 0..<Self.bandCount {
            let f0 = lo * pow(hi / lo, Double(b) / Double(Self.bandCount))
            let f1 = lo * pow(hi / lo, Double(b + 1) / Double(Self.bandCount))
            let i0 = max(1, Int(f0 / binHz)), i1 = min(half - 1, max(i0 + 1, Int(f1 / binHz)))
            var peak: Float = 0
            for i in i0..<i1 { peak = max(peak, mags[i]) }
            // dB → 0…1 (−50dB … 0dB so với biên độ đầy).
            let db = 20 * log10(max(peak / Float(n / 4), 1e-6))
            out[b] = min(1, max(0, (db + 50) / 50))
        }

        lock.lock()
        for b in 0..<Self.bandCount {
            // Lên nhanh, xuống chậm → nhảy theo nhịp mà không giật.
            let k: Float = out[b] > bands[b] ? 0.6 : 0.18
            bands[b] += (out[b] - bands[b]) * k
        }
        lastUpdate = CFAbsoluteTimeGetCurrent()
        lock.unlock()
    }
}
