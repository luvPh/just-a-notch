// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotchIsland", targets: ["NotchIsland"]),
        .library(name: "NotchIslandKit", targets: ["NotchIslandKit"])
    ],
    targets: [
        // All app logic lives in a library so both the app and the test/check
        // runners can link against it.
        .target(
            name: "NotchIslandKit",
            path: "Sources/NotchIslandKit",
            // Enable @testable import from the CLT-friendly check runner (debug only).
            swiftSettings: [.unsafeFlags(["-enable-testing"], .when(configuration: .debug))]
        ),
        // Thin executable: just launches the app.
        .executableTarget(
            name: "NotchIsland",
            dependencies: ["NotchIslandKit"],
            path: "Sources/App"
        )
    ]
)
