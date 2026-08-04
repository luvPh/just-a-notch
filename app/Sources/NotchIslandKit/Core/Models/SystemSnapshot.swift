// File: Sources/NotchIsland/Core/Models/SystemSnapshot.swift
import Foundation

/// Point-in-time snapshot of system metrics. Optional fields are `nil` when the
/// corresponding public API returns no usable value on this machine/OS.
struct SystemSnapshot: Equatable {
    var batteryPercentage: Double?   // 0...1
    var isCharging: Bool
    var timeToEmpty: TimeInterval?   // best-effort; often nil
    var cpuUsage: Double             // 0...1
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var diskUsed: UInt64
    var diskTotal: UInt64
    var uploadRate: UInt64           // bytes/sec, best-effort
    var downloadRate: UInt64         // bytes/sec, best-effort

    static let empty = SystemSnapshot(
        batteryPercentage: nil, isCharging: false, timeToEmpty: nil,
        cpuUsage: 0, memoryUsed: 0, memoryTotal: 0, diskUsed: 0, diskTotal: 0,
        uploadRate: 0, downloadRate: 0
    )

    var memoryUsedFraction: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }
    var diskUsedFraction: Double {
        diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0
    }
}

/// Human-readable byte formatting helper.
enum ByteFormat {
    static func string(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
    static func rate(_ bytesPerSec: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .binary) + "/s"
    }
}
