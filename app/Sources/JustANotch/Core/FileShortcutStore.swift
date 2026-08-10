import Foundation
import Combine

/// Giữ cây shortcut và lưu bền ra JSON. UI quan sát `root`.
final class FileShortcutStore: ObservableObject {
    @Published var root: Catalogue
    private let fileURL: URL

    /// Đường dẫn mặc định: ~/Library/Application Support/Just a Notch/shortcuts.json
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("shortcuts.json")
    }

    init(fileURL: URL = FileShortcutStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Catalogue.self, from: data) {
            self.root = decoded
        } else {
            self.root = Catalogue(name: "")
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(root) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
