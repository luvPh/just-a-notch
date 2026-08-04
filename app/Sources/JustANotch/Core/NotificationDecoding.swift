// File: Sources/JustANotch/Core/NotificationDecoding.swift
import Foundation

/// Decode a Notification Center `record.data` binary-plist payload into a
/// `NotificationRecord`. Returns nil when the payload cannot be parsed, has no
/// `req` dictionary, or carries no title/subtitle/body text — so callers can
/// skip unusable rows without special-casing.
func decodeNotification(id: Int64, bundleId: String, appName: String, payload: Data) -> NotificationRecord? {
    guard let root = try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil),
          let dict = root as? [String: Any],
          let req = dict["req"] as? [String: Any] else { return nil }

    let title = (req["titl"] as? String) ?? ""
    let subtitle = (req["subt"] as? String) ?? ""
    let body = (req["body"] as? String) ?? ""
    guard !(title.isEmpty && subtitle.isEmpty && body.isEmpty) else { return nil }

    let date: Date
    if let ts = req["date"] as? Double {
        date = Date(timeIntervalSinceReferenceDate: ts)
    } else {
        date = Date(timeIntervalSinceReferenceDate: 0)
    }

    return NotificationRecord(id: id, bundleId: bundleId, appName: appName,
                              title: title, subtitle: subtitle, body: body, date: date)
}

/// Tracks the highest already-seen `rec_id` so only genuinely new rows emit.
struct NewArrivalTracker {
    private(set) var lastSeenId: Int64?

    /// On start, adopt the current max without emitting existing rows as new.
    mutating func seed(maxId: Int64) { lastSeenId = maxId }

    func isNew(_ id: Int64) -> Bool {
        guard let lastSeenId else { return true }
        return id > lastSeenId
    }

    /// Advance the watermark; never moves backward.
    mutating func advance(to id: Int64) {
        lastSeenId = max(lastSeenId ?? Int64.min, id)
    }
}

/// Drop records whose age exceeds `maxAge`, preserving input order.
func prune(_ records: [NotificationRecord], now: Date, maxAge: TimeInterval) -> [NotificationRecord] {
    records.filter { now.timeIntervalSince($0.date) <= maxAge }
}

/// Group a flat record list by bundle id. Groups are ordered by their most
/// recent record (newest first); records within a group are newest first.
func groupByApp(_ records: [NotificationRecord]) -> [NotificationGroup] {
    var order: [String] = []
    var byBundle: [String: [NotificationRecord]] = [:]
    for r in records {
        if byBundle[r.bundleId] == nil { order.append(r.bundleId) }
        byBundle[r.bundleId, default: []].append(r)
    }
    let groups = order.map { bundle -> NotificationGroup in
        let recs = byBundle[bundle]!.sorted { $0.date > $1.date }
        return NotificationGroup(bundleId: bundle, appName: recs.first?.appName ?? bundle, records: recs)
    }
    return groups.sorted { ($0.records.first?.date ?? .distantPast) > ($1.records.first?.date ?? .distantPast) }
}
