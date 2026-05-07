// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceSwitcher",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "SpaceSwitcher",
            path: "Sources/SpaceSwitcher"
        )
    ]
)
