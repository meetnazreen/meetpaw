// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetPaw",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MeetPaw",
            path: "Sources/MeetPaw",
            // ponytail: Swift 5 language mode — not worth fighting Swift 6 strict
            // concurrency for a small menu-bar app. Bump to .v6 later if desired.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
