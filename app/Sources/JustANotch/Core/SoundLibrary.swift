import AppKit

/// Một lựa chọn âm: âm hệ thống (url == nil, tra bằng NSSound(named:)) hoặc
/// file đóng gói trong bundle Resources/Sounds/ (url != nil).
struct SoundOption: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let url: URL?
}

/// Thư viện âm: gộp âm hệ thống macOS và âm người dùng bỏ vào Resources/Sounds/.
final class SoundLibrary {
    static let shared = SoundLibrary()
    private(set) var available: [SoundOption] = []
    private var playing: NSSound?

    private init() { reload() }

    func reload() {
        var opts: [SoundOption] = []

        // Âm hệ thống trong /System/Library/Sounds (*.aiff).
        let sysDir = URL(fileURLWithPath: "/System/Library/Sounds")
        if let files = try? FileManager.default.contentsOfDirectory(at: sysDir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension.lowercased() == "aiff" {
                opts.append(SoundOption(name: f.deletingPathExtension().lastPathComponent, url: nil))
            }
        }

        // Âm đóng gói trong bundle Resources/Sounds/.
        if let bundleDir = Bundle.main.url(forResource: "Sounds", withExtension: nil),
           let files = try? FileManager.default.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil) {
            let exts: Set<String> = ["caf", "m4a", "aiff", "wav", "mp3"]
            for f in files where exts.contains(f.pathExtension.lowercased()) {
                opts.append(SoundOption(name: f.deletingPathExtension().lastPathComponent, url: f))
            }
        }

        available = opts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Tên âm hiển thị (cho dropdown).
    var names: [String] { available.map(\.name) }

    func play(_ name: String, volume: Float = 0.8) {
        let snd: NSSound?
        if let opt = available.first(where: { $0.name == name }), let url = opt.url {
            snd = NSSound(contentsOf: url, byReference: true)
        } else {
            snd = NSSound(named: name)
        }
        snd?.volume = volume
        // Giữ tham chiếu để âm file không bị giải phóng giữa chừng.
        playing = snd
        snd?.play()
    }
}
