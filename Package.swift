// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoteBubble",
    platforms: [.macOS(.v14)],
    products: [
        // Named so the build script can ask for just the app, leaving the
        // `@testable` test executable out of release builds.
        .executable(name: "NoteBubble", targets: ["NoteBubble"])
    ],
    targets: [
        // Thin launcher. Everything real lives in the core library so it can be tested.
        .executableTarget(
            name: "NoteBubble",
            dependencies: ["NoteBubbleCore"],
            path: "Sources/NoteBubble",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "NoteBubbleCore",
            path: "Sources/NoteBubbleCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Deliberately an executable, not a `.testTarget`: XCTest and swift-testing
        // both ship with Xcode, which this project does not depend on. Run with
        // `swift run NoteBubbleTests`.
        .executableTarget(
            name: "NoteBubbleTests",
            dependencies: ["NoteBubbleCore"],
            path: "Sources/NoteBubbleTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
