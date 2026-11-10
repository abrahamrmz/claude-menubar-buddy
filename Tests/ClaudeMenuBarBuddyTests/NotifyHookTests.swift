import Foundation
import Testing
import BuddyCore

// The REAL notify-done.sh on SessionEnd: it hands the payload to
// `buddy-rule session-end`, the only piece that turns a session id into a
// path. Same fixtures as HookTests: a throwaway $HOME, and a pgrep shim that
// here says the app is NOT running, because revoking must work anyway.
struct NotifyHookTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let script = root.appendingPathComponent("notify-done.sh")
    private static let ruleBinary = root.appendingPathComponent(".build/debug/buddy-rule")

    private struct Run {
        let stdout: String
        let status: Int32
        let seconds: TimeInterval
    }

    private struct Harness {
        let home: URL
        var configDir: URL { home.appendingPathComponent(".config/claude-menubar-buddy") }
        var store: SessionGrantStore { SessionGrantStore(configDirectory: configDir) }

        init() throws {
            home = FileManager.default.temporaryDirectory
                .appendingPathComponent("buddy-notify-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        }

        func cleanup() { try? FileManager.default.removeItem(at: home) }

        func grant(_ sessionID: String) -> Bool {
            store.grant(SessionGrant(agent: "claude", sessionID: sessionID, cwd: "/tmp/p", project: "p",
                                     grantedAt: Date().timeIntervalSince1970, trigger: "Bash: python3 x.py"))
        }

        func grantExists(_ sessionID: String) -> Bool {
            FileManager.default.fileExists(atPath: configDir.appendingPathComponent("session_auto/claude-\(sessionID).json").path)
        }

        func run(_ input: String, rule: String = NotifyHookTests.ruleBinary.path) throws -> Run {
            if !FileManager.default.isExecutableFile(atPath: NotifyHookTests.ruleBinary.path) {
                Issue.record("buddy-rule no está compilado: corre swift build antes de swift test")
            }
            let shimDir = home.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: shimDir, withIntermediateDirectories: true)
            let shim = shimDir.appendingPathComponent("pgrep")
            try "#!/bin/sh\nexit 1\n".write(to: shim, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [NotifyHookTests.script.path]
            process.environment = [
                "HOME": home.path,
                "PATH": "\(shimDir.path):/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
                "BUDDY_RULE": rule,
            ]
            let stdinPipe = Pipe(), stdoutPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            let start = Date()
            try process.run()
            stdinPipe.fileHandleForWriting.write(Data(input.utf8))
            stdinPipe.fileHandleForWriting.closeFile()
            let deadline = start.addingTimeInterval(10)
            while process.isRunning && Date() < deadline { usleep(10_000) }
            if process.isRunning {
                process.terminate()
                Issue.record("notify-done.sh did not exit within 10s")
            }
            process.waitUntilExit()
            let seconds = Date().timeIntervalSince(start)
            let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return Run(stdout: output.trimmingCharacters(in: .whitespacesAndNewlines),
                       status: process.terminationStatus, seconds: seconds)
        }
    }

    private let endedID = "d1538fa3-1006-4201-924b-8dafae43ffe3"   // the one in ClaudeHookFixtures.sessionEnd

    @Test func sessionEndRevokesThatSessionsGrantEvenWithTheAppClosed() throws {
        let h = try Harness()
        defer { h.cleanup() }
        #expect(h.grant(endedID))
        #expect(h.grant("ses-b"))
        let run = try h.run(ClaudeHookFixtures.sessionEnd)
        #expect(run.status == 0)
        #expect(run.stdout == "{}")
        #expect(!h.grantExists(endedID))
        #expect(h.grantExists("ses-b"))
        let log = (try? String(contentsOf: h.configDir.appendingPathComponent(AutoLog.fileName), encoding: .utf8)) ?? ""
        #expect(log.contains("apagada: fin de sesión"))
    }

    /// The folder is laid out so that gluing "claude-<id>.json" onto
    /// session_auto/ would land on the victim. Nothing may be deleted.
    @Test func aSessionIDWithDotsAndSlashesDeletesNothing() throws {
        let h = try Harness()
        defer { h.cleanup() }
        #expect(h.grant("x"))
        try FileManager.default.createDirectory(at: h.configDir.appendingPathComponent("session_auto/claude-x"),
                                                withIntermediateDirectories: true)
        let victim = h.configDir.appendingPathComponent("victim.json")
        try "{}".write(to: victim, atomically: true, encoding: .utf8)
        let run = try h.run(#"{"session_id":"x/../../victim","cwd":"/tmp/p","hook_event_name":"SessionEnd","reason":"other"}"#)
        #expect(run.stdout == "{}")
        #expect(FileManager.default.fileExists(atPath: victim.path))
        #expect(h.grantExists("x"))
    }

    @Test func withoutBuddyRuleItDoesNothingAndDoesNotFail() throws {
        let h = try Harness()
        defer { h.cleanup() }
        #expect(h.grant(endedID))
        let run = try h.run(ClaudeHookFixtures.sessionEnd, rule: "/nonexistent/buddy-rule")
        #expect(run.status == 0)
        #expect(run.stdout == "{}")
        #expect(h.grantExists(endedID))
    }

    /// Claude Code gives SessionEnd hooks 1.5 s unless settings say otherwise.
    @Test func sessionEndFitsWellInsideItsBudget() throws {
        let h = try Harness()
        defer { h.cleanup() }
        #expect(h.grant(endedID))
        let run = try h.run(ClaudeHookFixtures.sessionEnd)
        #expect(run.seconds < 1.0, "notify-done.sh took \(run.seconds) s on SessionEnd")
        #expect(!h.grantExists(endedID))
    }

    /// Only SessionEnd reaches buddy-rule: a stand-in rule leaves a mark if called.
    @Test func otherEventsDoNotCallBuddyRule() throws {
        let h = try Harness()
        defer { h.cleanup() }
        let mark = h.home.appendingPathComponent("called")
        let fake = h.home.appendingPathComponent("fake-rule")
        try "#!/bin/sh\ncat >/dev/null\ntouch '\(mark.path)'\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        for event in ["UserPromptSubmit", "PreCompact"] {
            let run = try h.run(#"{"session_id":"ses-a","cwd":"/tmp/p","hook_event_name":"\#(event)"}"#, rule: fake.path)
            #expect(run.stdout == "{}")
        }
        #expect(!FileManager.default.fileExists(atPath: mark.path))
    }
}
