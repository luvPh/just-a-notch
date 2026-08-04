// File: Sources/NotchIslandKit/Services/LaunchAtLoginService.swift
import Foundation
import ServiceManagement

/// Manages the "Launch at Login" state using `SMAppService` (macOS 13+).
/// On older systems it reports `.unsupported` rather than crashing.
final class LaunchAtLoginService {
    enum State: Equatable { case enabled, disabled, unsupported, requiresApproval }

    var isSupported: Bool {
        if #available(macOS 13.0, *) { return true } else { return false }
    }

    func currentState() -> State {
        guard #available(macOS 13.0, *) else { return .unsupported }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    /// Enable or disable. Returns the resulting state (or the error case).
    @discardableResult
    func setEnabled(_ enabled: Bool) -> State {
        guard #available(macOS 13.0, *) else { return .unsupported }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
        return currentState()
    }
}
