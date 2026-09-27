// File: Sources/JustANotch/Core/NotificationModels.swift
import Foundation

/// A single mirrored macOS notification. `id` is the Notification Center
/// database rowid (`rec_id`) — stable, unique, and monotonically increasing,
/// so records de-duplicate and order naturally.
struct NotificationRecord: Identifiable, Equatable {
    let id: Int64
    let bundleId: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    /// Deep link carried by the notification payload, when the sending app
    /// embeds one (e.g. `slack://channel?...`). Clicking the card opens this
    /// instead of merely activating the app. Nil for apps that embed nothing.
    var deepLink: URL? = nil

    /// Best single line of secondary text for compact display.
    var detailLine: String { body.isEmpty ? subtitle : body }
}

/// Whether the app can read the Notification Center database. `.denied` means
/// the open failed — almost always missing Full Disk Access.
enum NotificationPermissionState: Equatable {
    case unknown
    case granted
    case denied
}

/// One app's notifications, for the grouped history list.
struct NotificationGroup: Identifiable, Equatable {
    var id: String { bundleId }
    let bundleId: String
    let appName: String
    let records: [NotificationRecord]   // newest first
}
