import CoreGraphics

/// Người dùng có đang ngồi máy không — để lời nhắc đứng dậy bỏ lượt khi họ đã đi đâu đó.
enum UserPresence {
    /// Khoá màn hình, hoặc không có input (phím/chuột/trackpad) trong `idleThreshold` giây.
    static func isAway(idleThreshold: Double) -> Bool {
        if isScreenLocked { return true }
        guard let any = CGEventType(rawValue: ~0) else { return false }   // kCGAnyInputEventType
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any) > idleThreshold
    }

    static var isScreenLocked: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
