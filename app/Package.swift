// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "JustANotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "JustANotch",
            path: "Sources/JustANotch"
        ),
        .testTarget(
            name: "JustANotchTests",
            dependencies: ["JustANotch"],
            path: "Tests/JustANotchTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
