// File: Sources/NotchIsland/Core/Utilities/Log.swift
import Foundation
import OSLog

/// Centralised loggers, one per subsystem category.
/// Avoid logging sensitive data (notification bodies, secrets, private paths).
enum Log {
    private static let subsystem = "com.notchisland.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let window = Logger(subsystem: subsystem, category: "Window")
    static let island = Logger(subsystem: subsystem, category: "Island")
    static let media = Logger(subsystem: subsystem, category: "Media")
    static let system = Logger(subsystem: subsystem, category: "System")
    static let finder = Logger(subsystem: subsystem, category: "Finder")
    static let shortcut = Logger(subsystem: subsystem, category: "Shortcut")
    static let permission = Logger(subsystem: subsystem, category: "Permission")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
}
