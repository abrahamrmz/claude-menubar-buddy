import Foundation
import Testing
import BuddyCore

@Suite struct AutoLogEntryTests {
    private let grant = SessionGrant(agent: "claude", sessionID: "ses-a", cwd: "/tmp/proyX", project: "proyX",
                                     grantedAt: 1_800_000_000, trigger: "Bash: python3 x.py")

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("autolog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func anOldLineStillReads() throws {
        let old = #"{"ts":20,"agent":"claude","project":"q","cwd":"/q","tool":"Edit","hint":"h","category":"edicion"}"#
        let entry = try JSONDecoder().decode(AutoLogEntry.self, from: Data(old.utf8))
        #expect(entry == AutoLogEntry(ts: 20, agent: "claude", project: "q", cwd: "/q",
                                      tool: "Edit", hint: "h", category: "edicion"))
        #expect(entry.grant == nil)
        #expect(entry.session == nil)
    }

    @Test func absentFieldsAreNotWritten() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        AutoLog.append(AutoLogEntry(ts: 1, agent: "claude", project: "p", cwd: "/p", tool: "Bash",
                                    hint: "ls", category: "lectura"), in: dir)
        let line = try String(contentsOf: dir.appendingPathComponent(AutoLog.fileName), encoding: .utf8)
        #expect(!line.contains("grant"))
        #expect(!line.contains("session"))
    }

    @Test func grantAndSessionAreWrittenAndReadBack() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = AutoLogEntry(ts: 1, agent: "claude", project: "proyX", cwd: "/tmp/proyX", tool: "Bash",
                                 hint: "python3 x.py", category: "ejecuta", grant: "session", session: "ses-a")
        AutoLog.append(entry, in: dir)
        let line = try String(contentsOf: dir.appendingPathComponent(AutoLog.fileName), encoding: .utf8)
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        #expect(object?["grant"] as? String == "session")
        #expect(object?["session"] as? String == "ses-a")
        #expect(try JSONDecoder().decode(AutoLogEntry.self, from: Data(line.utf8)) == entry)
    }

    @Test func causesSayWhyTheGrantEnded() {
        #expect(GrantEnd.sessionEnded.rawValue == "fin de sesión")
        #expect(GrantEnd.menu.rawValue == "menú")
        #expect(GrantEnd.idle.rawValue == "8 h sin actividad")
        #expect(GrantEnd.all.rawValue == "todas")
    }

    @Test func grantStartedLine() {
        #expect(AutoLogEntry.grantStarted(grant, ts: 1_800_000_010) == AutoLogEntry(
            ts: 1_800_000_010, agent: "claude", project: "proyX", cwd: "/tmp/proyX", tool: "sesión",
            hint: "encendida: Bash: python3 x.py", category: "concesion", grant: "concesion", session: "ses-a"))
    }

    @Test func grantEndedLines() {
        let expected: [(GrantEnd, String)] = [
            (.sessionEnded, "apagada: fin de sesión"),
            (.menu, "apagada: menú"),
            (.idle, "apagada: 8 h sin actividad"),
            (.all, "apagada: todas"),
        ]
        for (cause, hint) in expected {
            #expect(AutoLogEntry.grantEnded(grant, cause: cause, ts: 1_800_000_020) == AutoLogEntry(
                ts: 1_800_000_020, agent: "claude", project: "proyX", cwd: "/tmp/proyX", tool: "sesión",
                hint: hint, category: "concesion", grant: "concesion", session: "ses-a"))
        }
    }
}
