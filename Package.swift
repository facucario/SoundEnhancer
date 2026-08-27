// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoundEnhancer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SoundEnhancer",
            path: "Sources/SoundEnhancer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SoundEnhancerTests",
            dependencies: ["SoundEnhancer"],
            path: "Tests/SoundEnhancerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
