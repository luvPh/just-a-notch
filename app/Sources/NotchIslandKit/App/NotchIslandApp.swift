// File: Sources/NotchIslandKit/App/NotchIslandApp.swift
import SwiftUI

/// The app scene. Declared `public` (without `@main`) so the thin executable
/// target can launch it via `NotchIslandApp.main()`.
public struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        Settings {
            SettingsRootView()
        }
    }
}
