// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TypeLock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TypeLock",
            path: "Sources"
        ),
    ]
)
