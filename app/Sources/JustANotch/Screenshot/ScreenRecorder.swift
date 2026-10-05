import AppKit
import AVFoundation
import ScreenCaptureKit

/// Quay màn hình bằng ScreenCaptureKit → AVAssetWriter (MP4 H.264, 60 fps, kèm
/// âm thanh hệ thống nếu bật). Chạy trên hàng đợi riêng; mọi gọi từ ngoài qua async.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url: URL
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoIn: AVAssetWriterInput?
    private var audioIn: AVAssetWriterInput?
    private var started = false
    private var firstPTS: CMTime = .invalid
    private var lastPTS: CMTime = .invalid
    private let q = DispatchQueue(label: "justanotch.recorder")

    var duration: Double {
        q.sync { firstPTS.isValid && lastPTS.isValid ? CMTimeGetSeconds(lastPTS - firstPTS) : 0 }
    }

    init(url: URL) { self.url = url }

    /// - filter: nội dung cần quay. - pixelSize: kích thước video (pixel).
    /// - sourceRect: vùng trong màn hình (pt, gốc trên-trái), nil = toàn bộ.
    func start(filter: SCContentFilter, pixelSize: CGSize, sourceRect: CGRect?, audio: Bool) async throws {
        // H.264 cần kích thước chẵn.
        let w = Int(pixelSize.width) & ~1, h = Int(pixelSize.height) & ~1
        let cfg = SCStreamConfiguration()
        cfg.width = w
        cfg.height = h
        if let r = sourceRect { cfg.sourceRect = r }
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.queueDepth = 6
        cfg.showsCursor = true
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.capturesAudio = audio
        cfg.excludesCurrentProcessAudio = true

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(4_000_000, w * h * 6),
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        v.expectsMediaDataInRealTime = true
        writer.add(v)
        if audio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000,
            ])
            a.expectsMediaDataInRealTime = true
            writer.add(a)
            audioIn = a
        }
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "rec", code: 1) }
        self.writer = writer
        videoIn = v

        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: q)
        if audio { try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: q) }
        try await s.startCapture()
        stream = s
    }

    /// Dừng + ghi xong file. Trả về false nếu chưa kịp có khung hình nào.
    func stop() async -> Bool {
        try? await stream?.stopCapture()
        stream = nil
        return await withCheckedContinuation { cont in
            q.async { [self] in
                guard let writer, started else {
                    writer?.cancelWriting()
                    cont.resume(returning: false); return
                }
                videoIn?.markAsFinished()
                audioIn?.markAsFinished()
                writer.endSession(atSourceTime: lastPTS)
                writer.finishWriting { cont.resume(returning: writer.status == .completed) }
            }
        }
    }

    func cancel() async {
        try? await stream?.stopCapture()
        stream = nil
        q.sync { writer?.cancelWriting() }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid, let writer, writer.status == .writing else { return }
        switch type {
        case .screen:
            // Chỉ khung hình hoàn chỉnh (bỏ khung "idle"/"blank").
            guard let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let raw = att.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            let pts = sb.presentationTimeStamp
            if !started {
                writer.startSession(atSourceTime: pts)
                firstPTS = pts
                started = true
            }
            if let v = videoIn, v.isReadyForMoreMediaData { v.append(sb); lastPTS = pts }
        case .audio:
            guard started, let a = audioIn, a.isReadyForMoreMediaData else { return }
            a.append(sb)
        default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {}
}
