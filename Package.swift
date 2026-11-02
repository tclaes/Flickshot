// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LightShot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LightShot",
            path: "Sources/LightShot",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
