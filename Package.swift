// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeMenuBarBuddy",
    platforms: [.macOS(.v13)],
    dependencies: [
        // User-remappable global hotkeys (Carbon under the hood, no
        // Accessibility permission — same trade-off as our old raw Carbon).
        // Pinned below 1.10: from 1.10.0 Recorder.swift uses #Preview
        // macros, which don't compile with Command Line Tools only (the
        // PreviewsMacros plugin ships with full Xcode, and this project
        // deliberately builds with bare `swift build`).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMinor(from: "1.9.4")),
        // Type-safe UserDefaults; same underlying keys as before, so
        // existing user settings carry over untouched.
        .package(url: "https://github.com/sindresorhus/Defaults", from: "8.2.0"),
        // Preferences window framework (used from Fase 2.1 onward).
        .package(url: "https://github.com/sindresorhus/Settings", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeMenuBarBuddy",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Settings", package: "Settings"),
            ],
            path: "Sources/ClaudeMenuBarBuddy",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
