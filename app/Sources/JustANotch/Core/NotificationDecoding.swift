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

    // The delivery date lives at the TOP LEVEL of the payload, not in `req`.
    // Fall back to "now" (never 2001) so a missing/unexpected date can't make the
    // record look 25 years old and get pruned out of the 8-hour history.
    let date = parseNotificationDate(top: dict, req: req) ?? Date()

    return NotificationRecord(id: id, bundleId: bundleId, appName: appName,
                              title: title, subtitle: subtitle, body: body, date: date)
}

/// Resolve a notification's timestamp. A binary-plist date value deserializes to
/// `Date`; some payloads store it as a number of seconds in the Cocoa reference
/// epoch (2001-01-01). The top-level `date` is preferred over any `req` date.
/// Returns nil when neither carries a usable value.
func parseNotificationDate(top: [String: Any], req: [String: Any]) -> Date? {
    for value in [top["date"], req["date"]] {
        if let d = value as? Date { return d }
        if let n = value as? NSNumber { return Date(timeIntervalSinceReferenceDate: n.doubleValue) }
    }
    return nil
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
