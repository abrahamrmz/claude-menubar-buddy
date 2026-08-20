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
        // The pure logic — burn-rate math, mood policy — split out of the
        // executable so `swift test` can reach it. SPM can't link tests
        // against an executable target's symbols without Xcode machinery,
        // and this project builds with bare Command Line Tools on purpose.
        .target(
            name: "BuddyCore",
            path: "Sources/BuddyCore"
        ),
        .executableTarget(
            name: "ClaudeMenuBarBuddy",
            dependencies: [
                "BuddyCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Defaults", package: "Defaults"),
                .product(name: "Settings", package: "Settings"),
            ],
            path: "Sources/ClaudeMenuBarBuddy",
            resources: [
                .copy("Resources")
            ]
        ),
        // Also hosts the hook.sh fixture harness (HookTests), which shells
        // out to the real script — see Tests/ClaudeMenuBarBuddyTests.
        .testTarget(
            name: "ClaudeMenuBarBuddyTests",
            dependencies: ["BuddyCore"],
            path: "Tests/ClaudeMenuBarBuddyTests"
        ),
    ]
)
