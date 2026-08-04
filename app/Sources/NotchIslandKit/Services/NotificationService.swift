// File: Sources/NotchIsland/Services/NotificationService.swift
import Foundation
import UserNotifications

/// Level 1 + Level 2 notifications only (per trimmed scope):
/// - Level 1: internal island events (handled by `IslandViewModel`).
/// - Level 2: the app's OWN user notifications via `UNUserNotificationCenter`.
/// Level 3 (mirroring other apps' Notification Center) is intentionally NOT
/// implemented — macOS has no public API for it.
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    /// Request authorization lazily — only call when the user enables the
    /// notifications feature.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { Log.permission.error("Notif auth error: \(error.localizedDescription, privacy: .public)") }
            completion(granted)
        }
    }

    func authorizationState(completion: @escaping (PermissionState) -> Void) {
        center.getNotificationSettings { settings in
            let state: PermissionState
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: state = .granted
            case .denied: state = .denied
            case .notDetermined: state = .notDetermined
            @unknown default: state = .unknown
            }
            completion(state)
        }
    }

    /// Post one of the app's own notifications. Title/body should not contain
    /// sensitive data (nothing is logged here).
    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { Log.app.error("Notif post failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

/// Permission model shared across services (Phase 7 surfaces these in Settings).
enum PermissionState: Equatable {
    case unknown
    case notDetermined
    case denied
    case granted
    case restricted
    case unsupported
}
