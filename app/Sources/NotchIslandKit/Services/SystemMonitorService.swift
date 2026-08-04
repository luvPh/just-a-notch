// File: Sources/NotchIsland/Services/SystemMonitorService.swift
import Foundation
import Combine
import Darwin
import IOKit.ps

/// Collects battery, CPU, memory and disk metrics using public APIs, with
/// controlled polling that slows down when the island is not visible. Network
/// rate is best-effort and may report 0 where unavailable.
final class SystemMonitorService: SystemMonitorServiceProtocol {
    let snapshot = CurrentValueSubject<SystemSnapshot, Never>(.empty)

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.notchisland.sysmon", qos: .utility)
    private var active = false
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    private var interval: TimeInterval { active ? 2.0 : 10.0 }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.collect() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() { queue.async { [weak self] in self?.collect() } }

    func setActive(_ active: Bool) {
        guard active != self.active else { return }
        self.active = active
        if timer != nil { start() } // reschedule at new interval
    }

    // MARK: - Collection

    private func collect() {
        var snap = SystemSnapshot.empty
        if let battery = Self.batteryInfo() {
            snap.batteryPercentage = battery.percentage
            snap.isCharging = battery.charging
            snap.timeToEmpty = battery.timeToEmpty
        }
        snap.cpuUsage = cpuUsage()
        let mem = Self.memoryInfo()
        snap.memoryUsed = mem.used
        snap.memoryTotal = mem.total
        let disk = Self.diskInfo()
        snap.diskUsed = disk.used
        snap.diskTotal = disk.total
        snapshot.send(snap)
    }

    // MARK: - Battery (IOKit power sources)

    private static func batteryInfo() -> (percentage: Double, charging: Bool, timeToEmpty: TimeInterval?)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else { return nil }

        guard let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
              let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        let state = desc[kIOPSPowerSourceStateKey] as? String
        let charging = (state == kIOPSACPowerValue) || (desc[kIOPSIsChargingKey] as? Bool ?? false)
        var timeToEmpty: TimeInterval?
        if let minutes = desc[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
            timeToEmpty = TimeInterval(minutes * 60)
        }
        return (Double(capacity) / Double(max), charging, timeToEmpty)
    }

    // MARK: - CPU (host_statistics load ticks)

    private func cpuUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPtr, &size)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot.value.cpuUsage }

        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        defer { previousCPUTicks = (user, system, idle, nice) }
        guard let prev = previousCPUTicks else { return 0 }

        let userD = Double(user &- prev.user)
        let systemD = Double(system &- prev.system)
        let idleD = Double(idle &- prev.idle)
        let niceD = Double(nice &- prev.nice)
        let total = userD + systemD + idleD + niceD
        guard total > 0 else { return 0 }
        return (userD + systemD + niceD) / total
    }

    // MARK: - Memory (host_statistics64 vm stats)

    private static func memoryInfo() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &size)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let pageSize = UInt64(vm_kernel_page_size)
        // "Used" ~ active + wired + compressed (excludes purgeable/inactive cache).
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        return (used, total)
    }

    // MARK: - Disk

    private static func diskInfo() -> (used: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity else { return (0, 0) }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        let totalU = UInt64(total)
        let usedU = totalU > UInt64(available) ? totalU - UInt64(available) : 0
        return (usedU, totalU)
    }
}
