import AppKit
import ApplicationServices

/// Bấm thông báo "như native": tìm đúng thông báo đó trong Notification Center của
/// macOS (qua Accessibility) rồi nhấn nó → app gốc nhận đúng hành động mặc định
/// (mở đúng cuộc trò chuyện, email, ticket…) giống hệt người dùng tự bấm.
///
/// Cần quyền Accessibility. Không tìm thấy (đã bị xoá khỏi NC, chưa cấp quyền…)
/// → `completion(false)` để caller rơi về deep link / mở app.
@MainActor
enum NotificationClicker {
    private static let ncBundle = "com.apple.notificationcenterui"
    private static let ccBundle = "com.apple.controlcenter"

    static func click(_ r: NotificationRecord, completion: @escaping (Bool) -> Void) {
        guard AXIsProcessTrusted(), let nc = app(ncBundle) else { completion(false); return }
        // 1) Banner còn đang hiện / NC đang mở sẵn → bấm luôn.
        if press(r, in: nc) { completion(true); return }
        // 2) Mở Notification Center (bấm đồng hồ trên thanh menu) rồi tìm trong danh sách.
        guard toggleNotificationCenter() else { completion(false); return }
        poll(r, nc: nc, tries: 12, completion: completion)
    }

    private static func poll(_ r: NotificationRecord, nc: AXUIElement, tries: Int,
                             completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if press(r, in: nc) { completion(true); return }
            if tries <= 0 {
                _ = toggleNotificationCenter()   // đóng lại, trả về như cũ
                completion(false)
                return
            }
            poll(r, nc: nc, tries: tries - 1, completion: completion)
        }
    }

    // MARK: Tìm + nhấn

    /// Tìm phần tử thông báo khớp và nhấn. Nhóm thông báo (stack) → nhấn để bung
    /// rồi tìm lại một lần.
    private static func press(_ r: NotificationRecord, in nc: AXUIElement) -> Bool {
        guard let hit = find(r, in: nc) else { return false }
        if (string(hit, kAXSubroleAttribute) ?? "").contains("Stack") {
            AXUIElementPerformAction(hit, kAXPressAction as CFString)
            usleep(250_000)
            guard let inner = find(r, in: nc, skipStacks: true) else { return false }
            return AXUIElementPerformAction(inner, kAXPressAction as CFString) == .success
        }
        return AXUIElementPerformAction(hit, kAXPressAction as CFString) == .success
    }

    private static func find(_ r: NotificationRecord, in root: AXUIElement, skipStacks: Bool = false) -> AXUIElement? {
        let needles = [r.title, r.subtitle, String(r.body.prefix(40))]
            .map(normalize).filter { !$0.isEmpty }
        guard let first = needles.first else { return nil }
        var best: (AXUIElement, Int)?
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 4000 {
            let (el, depth) = queue.removeFirst()
            visited += 1
            if actions(el).contains(kAXPressAction) {
                let sub = string(el, kAXSubroleAttribute) ?? ""
                if !(skipStacks && sub.contains("Stack")) {
                    let text = normalize(label(el))
                    // Khớp tiêu đề bắt buộc; khớp thêm thân/phụ đề thì điểm cao hơn.
                    if text.contains(first) {
                        let score = needles.filter { text.contains($0) }.count * 10 + depth
                        if best == nil || score > best!.1 { best = (el, score) }
                    }
                }
            }
            if depth < 14 {
                for c in children(el) { queue.append((c, depth + 1)) }
            }
        }
        return best?.0
    }

    /// Nhãn đọc được của phần tử: mô tả/tiêu đề + chữ của các con gần (≤ 3 tầng).
    private static func label(_ el: AXUIElement) -> String {
        var parts = [string(el, kAXDescriptionAttribute), string(el, kAXTitleAttribute),
                     string(el, kAXValueAttribute)].compactMap { $0 }
        func walk(_ e: AXUIElement, _ d: Int) {
            guard d < 3 else { return }
            for c in children(e) {
                if let v = string(c, kAXValueAttribute) { parts.append(v) }
                if let v = string(c, kAXDescriptionAttribute) { parts.append(v) }
                walk(c, d + 1)
            }
        }
        walk(el, 0)
        return parts.joined(separator: " ")
    }

    // MARK: Mở/đóng Notification Center

    /// Bấm đồng hồ trên thanh menu (Control Center) — cách macOS mở NC.
    private static func toggleNotificationCenter() -> Bool {
        guard let cc = app(ccBundle) else { return false }
        var bar: AnyObject?
        AXUIElementCopyAttributeValue(cc, "AXExtrasMenuBar" as CFString, &bar)
        guard let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
        let clock = children(bar as! AXUIElement).first {
            (string($0, kAXIdentifierAttribute) ?? "") == "com.apple.menuextra.clock"
        }
        guard let clock else { return false }
        return AXUIElementPerformAction(clock, kAXPressAction as CFString) == .success
    }

    // MARK: AX helpers

    private static func app(_ bundle: String) -> AXUIElement? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var v: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v)
        return (v as? [AXUIElement]) ?? []
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func actions(_ el: AXUIElement) -> [String] {
        var v: CFArray?
        AXUIElementCopyActionNames(el, &v)
        return (v as? [String]) ?? []
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
