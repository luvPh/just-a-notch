// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchProto",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchProto",
            path: "Sources/NotchProto"
        )
    ]
)
