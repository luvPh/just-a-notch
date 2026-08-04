// File: Sources/JustANotch/Core/NotificationService.swift
import Foundation
import Combine
import AppKit
import SQLite3

protocol NotificationServiceProtocol: AnyObject {
    /// Fires once per newly delivered notification (drives the HUD).
    var latestArrival: PassthroughSubject<NotificationRecord, Never> { get }
    /// Retained history, newest first, already pruned to the last 8 hours.
    var history: CurrentValueSubject<[NotificationRecord], Never> { get }
    /// Whether the Notification Center database can be read.
    var permissionState: CurrentValueSubject<NotificationPermissionState, Never> { get }
    /// Cached app icon for a bundle id (generic bell fallback).
    func icon(forBundle bundleId: String) -> NSImage
    func start()
    func stop()
}

final class NotificationService: NotificationServiceProtocol {
    let latestArrival = PassthroughSubject<NotificationRecord, Never>()
    let history = CurrentValueSubject<[NotificationRecord], Never>([])
    let permissionState = CurrentValueSubject<NotificationPermissionState, Never>(.unknown)

    private let maxAge: TimeInterval = 8 * 3600
    private let queue = DispatchQueue(label: "com.notchisland.notifications", qos: .utility)
    private var pollTimer: DispatchSourceTimer?
    private var db: OpaquePointer?
    private var tracker = NewArrivalTracker()

    // Accessed only on `queue`.
    private var records: [NotificationRecord] = []
    private var iconCache: [String: NSImage] = [:]
    private var nameCache: [String: String] = [:]

    private static let dbPath = ("~/Library/Group Containers/group.com.apple.usernoted/db2/db" as NSString)
        .expandingTildeInPath

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 2.0)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        pollTimer = t
    }

    func stop() {
        pollTimer?.cancel(); pollTimer = nil
        if let db { sqlite3_close(db) }
        db = nil
    }

    // MARK: - Poll loop (on `queue`)

    private func tick() {
        guard ensureOpen() else { return }   // sets .denied + leaves db nil on failure
        if tracker.lastSeenId == nil { seedWatermark(); return }
        fetchNewRows()
        pruneAndPublish()
    }

    /// Open the DB read-only if not already open. Publishes permission state.
    private func ensureOpen() -> Bool {
        if db != nil { return true }
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(Self.dbPath, &handle, SQLITE_OPEN_READONLY, nil)
        if rc == SQLITE_OK, let handle {
            db = handle
            publishPermission(.granted)
            return true
        }
        if let handle { sqlite3_close(handle) }
        publishPermission(.denied)
        return false
    }

    private func seedWatermark() {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &stmt, nil) == SQLITE_OK else {
            tracker.seed(maxId: 0); return
        }
        let maxId: Int64 = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
        tracker.seed(maxId: maxId)
    }

    private func fetchNewRows() {
        guard let lastSeen = tracker.lastSeenId else { return }
        let sql = """
        SELECT r.rec_id, a.identifier, r.data
        FROM record r JOIN app a ON a.app_id = r.app_id
        WHERE r.rec_id > ? ORDER BY r.rec_id ASC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(stmt, 1, lastSeen)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let recId = sqlite3_column_int64(stmt, 0)
            let bundleId = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard let blob = sqlite3_column_blob(stmt, 2) else { tracker.advance(to: recId); continue }
            let len = Int(sqlite3_column_bytes(stmt, 2))
            let data = Data(bytes: blob, count: len)

            tracker.advance(to: recId)
            let appName = displayName(forBundle: bundleId)
            guard let record = decodeNotification(id: recId, bundleId: bundleId,
                                                  appName: appName, payload: data) else { continue }
            records.append(record)
            let arrival = record
            DispatchQueue.main.async { [weak self] in self?.latestArrival.send(arrival) }
        }
    }

    private func pruneAndPublish() {
        records = prune(records, now: Date(), maxAge: maxAge)
        let snapshot = records.sorted { $0.date > $1.date }   // newest first
        DispatchQueue.main.async { [weak self] in self?.history.send(snapshot) }
    }

    private func publishPermission(_ state: NotificationPermissionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.permissionState.value != state else { return }
            self.permissionState.send(state)
        }
    }

    // MARK: - App metadata (on `queue`, cached)

    private func appURL(forBundle bundleId: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    private func displayName(forBundle bundleId: String) -> String {
        if let cached = nameCache[bundleId] { return cached }
        let name = appURL(forBundle: bundleId).flatMap {
            FileManager.default.displayName(atPath: $0.path)
        }?.replacingOccurrences(of: ".app", with: "") ?? bundleId
        nameCache[bundleId] = name
        return name
    }

    func icon(forBundle bundleId: String) -> NSImage {
        // Safe to call from the main thread; cache is only mutated on `queue`,
        // but reads of NSImage here are fine for display. Guard with a sync hop.
        queue.sync {
            if let cached = iconCache[bundleId] { return cached }
            let image: NSImage
            if let url = appURL(forBundle: bundleId) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil) ?? NSImage()
            }
            iconCache[bundleId] = image
            return image
        }
    }
}
