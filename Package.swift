// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flickshot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Flickshot",
            path: "Sources/Flickshot",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
