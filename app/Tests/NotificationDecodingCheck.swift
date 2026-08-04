// File: Tests/NotificationDecodingCheck.swift
import Foundation

private func check(_ cond: Bool, _ message: String,
                   file: StaticString = #filePath, line: UInt = #line) {
    if !cond { fatalError("\(file):\(line): \(message)") }
}

/// Build a Notification Center-style payload plist BLOB for testing decode.
/// The real payload carries the delivery date at the TOP LEVEL (`topDate`);
/// `reqDate` covers the (rarer) case where a date sits inside `req`.
private func payload(titl: String? = nil, subt: String? = nil, body: String? = nil,
                     topDate: Any? = nil, reqDate: Double? = nil) -> Data {
    var req: [String: Any] = [:]
    if let titl { req["titl"] = titl }
    if let subt { req["subt"] = subt }
    if let body { req["body"] = body }
    if let reqDate { req["date"] = reqDate }
    var root: [String: Any] = ["req": req]
    if let topDate { root["date"] = topDate }
    return try! PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
}

@main
struct NotificationDecodingCheck {
    static func main() {
        // --- decode: full payload, delivery date at the TOP LEVEL (real shape) ---
        let refDate = Date(timeIntervalSinceReferenceDate: 700_000_000.0)
        let full = decodeNotification(id: 42, bundleId: "com.apple.iChat", appName: "Messages",
                                      payload: payload(titl: "Alice", subt: "iMessage",
                                                       body: "Hello there", topDate: refDate))
        check(full != nil, "full payload should decode")
        check(full!.id == 42, "id maps from rec_id")
        check(full!.title == "Alice", "title maps from titl")
        check(full!.subtitle == "iMessage", "subtitle maps from subt")
        check(full!.body == "Hello there", "body maps from body")
        check(full!.date == refDate, "date comes from the top-level plist date")

        // --- decode: numeric top-level date parsed as Cocoa reference epoch ---
        let numDate = decodeNotification(id: 43, bundleId: "x", appName: "X",
                                         payload: payload(titl: "Hi", topDate: 700_000_000.0))
        check(numDate?.date == Date(timeIntervalSinceReferenceDate: 700_000_000.0),
              "numeric top-level date uses reference epoch")

        // --- decode: req-level date still honored when no top-level date ---
        let reqDate = decodeNotification(id: 44, bundleId: "x", appName: "X",
                                         payload: payload(titl: "Hi", reqDate: 700_000_000.0))
        check(reqDate?.date == Date(timeIntervalSinceReferenceDate: 700_000_000.0),
              "req.date used as fallback when no top-level date")

        // --- decode: no date anywhere → recent fallback, NOT 2001 (so it isn't pruned) ---
        let noDate = decodeNotification(id: 45, bundleId: "x", appName: "X", payload: payload(titl: "Hi"))
        check(noDate != nil, "record without any date still decodes")
        check(abs(noDate!.date.timeIntervalSinceNow) < 5, "missing date falls back to ~now, not 2001")

        // --- parseNotificationDate helper ---
        check(parseNotificationDate(top: ["date": Date(timeIntervalSinceReferenceDate: 5)], req: ["date": 9.0])
                == Date(timeIntervalSinceReferenceDate: 5), "top-level date preferred over req")
        check(parseNotificationDate(top: [:], req: ["date": 9.0]) == Date(timeIntervalSinceReferenceDate: 9),
              "falls back to req numeric date")
        check(parseNotificationDate(top: [:], req: [:]) == nil, "nil when no date present")

        // --- decode: missing subtitle/body tolerated ---
        let titleOnly = decodeNotification(id: 1, bundleId: "x", appName: "X",
                                           payload: payload(titl: "Ping"))
        check(titleOnly != nil, "title-only payload should decode")
        check(titleOnly!.subtitle.isEmpty && titleOnly!.body.isEmpty, "missing subt/body become empty")

        // --- decode: all-empty payload skipped ---
        check(decodeNotification(id: 2, bundleId: "x", appName: "X", payload: payload()) == nil,
              "all-empty payload is skipped")

        // --- decode: missing `req` skipped ---
        let noReq = try! PropertyListSerialization.data(fromPropertyList: ["other": 1], format: .binary, options: 0)
        check(decodeNotification(id: 3, bundleId: "x", appName: "X", payload: noReq) == nil,
              "payload without req is skipped")

        // --- decode: garbage bytes skipped, no crash ---
        check(decodeNotification(id: 4, bundleId: "x", appName: "X", payload: Data([0x00, 0x01, 0x02])) == nil,
              "undecodable bytes are skipped")

        // --- new-arrival tracker ---
        var tracker = NewArrivalTracker()
        check(tracker.lastSeenId == nil, "tracker starts empty")
        tracker.seed(maxId: 100)                       // seeding emits nothing
        check(tracker.lastSeenId == 100, "seed sets lastSeenId")
        check(tracker.isNew(99) == false, "older id is not new")
        check(tracker.isNew(100) == false, "equal id is not new")
        check(tracker.isNew(101) == true, "higher id is new")
        tracker.advance(to: 105)
        check(tracker.lastSeenId == 105, "advance moves lastSeenId forward")
        tracker.advance(to: 103)
        check(tracker.lastSeenId == 105, "advance never moves backward")

        // --- prune: drop older than 8h ---
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func rec(_ id: Int64, ageHours: Double) -> NotificationRecord {
            NotificationRecord(id: id, bundleId: "b", appName: "B", title: "t",
                               subtitle: "", body: "", date: now.addingTimeInterval(-ageHours * 3600))
        }
        let pruned = prune([rec(1, ageHours: 9), rec(2, ageHours: 7.9), rec(3, ageHours: 0)],
                           now: now, maxAge: 8 * 3600)
        check(pruned.map(\.id) == [2, 3], "prune drops records older than 8h, keeps newer")

        // --- groupByApp: per-app, newest-group first, newest-in-group first ---
        func recA(_ id: Int64, bundle: String, app: String, ageMin: Double) -> NotificationRecord {
            NotificationRecord(id: id, bundleId: bundle, appName: app, title: "t",
                               subtitle: "", body: "", date: now.addingTimeInterval(-ageMin * 60))
        }
        let groups = groupByApp([
            recA(1, bundle: "mail", app: "Mail", ageMin: 30),
            recA(2, bundle: "msg", app: "Messages", ageMin: 10),
            recA(3, bundle: "mail", app: "Mail", ageMin: 5),
        ])
        check(groups.map(\.bundleId) == ["mail", "msg"],
              "groups ordered by most-recent record (mail has id=3 at 5min)")
        check(groups[0].records.map(\.id) == [3, 1], "records newest-first within a group")

        print("NotificationDecodingCheck PASSED")
    }
}
