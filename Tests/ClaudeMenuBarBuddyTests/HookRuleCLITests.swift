import Foundation
import Testing
import BuddyCore

@Suite struct HookRuleCLITests {
    private struct Home {
        let url: URL
        var config: URL { url.appendingPathComponent(".config/claude-menubar-buddy") }
        init(autoMode: Bool = false, allowlist: String? = nil) throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("cli-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
            if autoMode { try Data().write(to: config.appendingPathComponent("auto_mode")) }
            if let a = allowlist { try a.write(to: config.appendingPathComponent("always_allow.json"), atomically: true, encoding: .utf8) }
        }
        func run(_ input: [String: Any]) throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: input)
            let out = HookRuleCLI.run(input: data, environment: ["HOME": url.path, "PATH": "/usr/bin:/bin"])
            return try JSONSerialization.jsonObject(with: out) as! [String: Any]
        }
        func autoLogLines() -> [String] {
            let text = (try? String(contentsOf: config.appendingPathComponent(AutoLog.fileName), encoding: .utf8)) ?? ""
            return text.split(separator: "\n").map(String.init)
        }
        func runRaw(_ text: String) throws -> [String: Any] {
            let out = HookRuleCLI.run(input: Data(text.utf8), environment: ["HOME": url.path, "PATH": "/usr/bin:/bin"])
            return try JSONSerialization.jsonObject(with: out) as! [String: Any]
        }
        func sessionEnd(_ text: String) -> String {
            String(decoding: HookRuleCLI.sessionEnd(input: Data(text.utf8), environment: ["HOME": url.path]), as: UTF8.self)
        }
        var store: SessionGrantStore { SessionGrantStore(configDirectory: config) }
        /// A grant as the card's button would write it, last active at `at`.
        func grant(_ sessionID: String, agent: String = "claude", cwd: String = "/tmp/proyX", at: Date = Date()) -> Bool {
            store.grant(SessionGrant(agent: agent, sessionID: sessionID, cwd: cwd,
                                     project: (cwd as NSString).lastPathComponent,
                                     grantedAt: at.timeIntervalSince1970, trigger: "Bash: python3 x.py"), now: at)
        }
        func grantFile(_ sessionID: String, agent: String = "claude") -> URL {
            config.appendingPathComponent("session_auto/\(agent)-\(sessionID).json")
        }
        func lastActivity(_ sessionID: String) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: grantFile(sessionID).path))?[.modificationDate] as? Date
        }
    }

    private func bash(_ c: String, plan: Bool = false, session: String? = nil) -> [String: Any] {
        var i: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": c], "cwd": "/tmp/proyX"]
        if plan { i["permission_mode"] = "plan" }
        if let session { i["session_id"] = session }
        return i
    }

    @Test func outputHasExactlyTheContractKeys() throws {
        let out = try Home().run(bash("git status"))
        #expect(Set(out.keys) == ["ask_on_timeout", "category", "critical", "grant", "reason",
                                  "session_coverable", "verdict"])
    }

    @Test func autoOffCardsAReadButClassifiesIt() throws {
        let out = try Home().run(bash("git status"))
        #expect(out["verdict"] as? String == "card")
        #expect(out["category"] as? String == "lectura")
        #expect(out["critical"] as? Bool == false)
        #expect(out["grant"] is NSNull)
    }

    @Test func autoOnPassesAndLogs() throws {
        let home = try Home(autoMode: true)
        let out = try home.run(bash("git status"))
        #expect(out["verdict"] as? String == "pass")
        #expect(out["grant"] as? String == "auto")
        #expect((out["reason"] as? String ?? "").contains("Modo auto (lectura)"))
        let lines = home.autoLogLines()
        #expect(lines.count == 1)
        let entry = try JSONDecoder().decode(AutoLogEntry.self, from: Data(lines[0].utf8))
        #expect(entry.agent == "claude")
        #expect(entry.tool == "Bash")
        #expect(entry.category == "lectura")
        #expect(entry.hint == "git status")
        #expect(entry.project == "proyX")
    }

    @Test func planModeDefersAndDoesNotLog() throws {
        let home = try Home(autoMode: true)
        #expect(try home.run(bash("git status", plan: true))["verdict"] as? String == "defer")
        #expect(home.autoLogLines().isEmpty)
    }

    @Test func criticalCardCarriesItsReason() throws {
        let out = try Home(autoMode: true).run(bash("python3 x.py"))
        #expect(out["verdict"] as? String == "card")
        #expect(out["critical"] as? Bool == true)
        #expect(out["reason"] as? String == "ejecuta código: python3")
    }

    @Test func alwaysAllowReasonKeepsItsWording() throws {
        let out = try Home(allowlist: #"{"global":["git"],"projects":{}}"#).run(bash("git status"))
        #expect(out["grant"] as? String == "always")
        #expect(out["reason"] as? String == "Always-allowed everywhere via Claude Menu Bar Buddy: git")
    }

    @Test func alwaysAllowCannotGrantCritical() throws {
        let out = try Home(allowlist: #"{"global":["npm"],"projects":{}}"#).run(bash("npm test"))
        #expect(out["verdict"] as? String == "card")
    }

    @Test func editsPassUnlessProtected() throws {
        let home = try Home(autoMode: true)
        let plain = try home.run(["tool_name": "Edit", "tool_input": ["file_path": "/tmp/proyX/notes.txt"], "cwd": "/tmp/proyX"])
        #expect(plain["verdict"] as? String == "pass")
        let zshrc = try home.run(["tool_name": "Write", "tool_input": ["file_path": home.url.path + "/.zshrc"], "cwd": "/tmp/proyX"])
        #expect(zshrc["verdict"] as? String == "card")
        #expect(zshrc["category"] as? String == "ruta_protegida")
    }

    @Test func webAndQuestions() throws {
        let home = try Home(autoMode: true)
        let web = try home.run(["tool_name": "WebFetch", "tool_input": ["url": "https://x"], "cwd": "/tmp"])
        #expect(web["critical"] as? Bool == true)
        let q = try home.run(["tool_name": "AskUserQuestion", "tool_input": [:], "cwd": "/tmp"])
        #expect(q["verdict"] as? String == "card")
        #expect(q["category"] as? String == "pregunta")
        #expect(q["critical"] as? Bool == false)
    }

    @Test(arguments: ["", "{not json", "[1,2]"])
    func invalidInputIsACriticalCard(text: String) throws {
        let out = HookRuleCLI.run(input: Data(text.utf8), environment: ["HOME": "/nonexistent"])
        let obj = try JSONSerialization.jsonObject(with: out) as! [String: Any]
        #expect(obj["verdict"] as? String == "card")
        #expect(obj["critical"] as? Bool == true)
    }

    @Test func missingFieldsDoNotCrash() throws {
        let out = try Home(autoMode: true).run(["tool_name": "Bash"])
        #expect(out["verdict"] as? String == "card")
    }

    @Test func concurrentAppendsStayWholeLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.concurrentPerform(iterations: 20) { i in
            AutoLog.append(AutoLogEntry(ts: Double(i), agent: "claude", project: "p", cwd: "/p", tool: "Bash",
                                        hint: String(repeating: "x", count: 300), category: "lectura"), in: dir)
        }
        let lines = try String(contentsOf: dir.appendingPathComponent(AutoLog.fileName), encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 20)
        for line in lines { #expect((try? JSONDecoder().decode(AutoLogEntry.self, from: Data(line.utf8))) != nil) }
    }

    @Test func rotatesAtTheLimit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<10 {
            AutoLog.append(AutoLogEntry(ts: Double(i), agent: "claude", project: "p", cwd: "/p", tool: "Bash",
                                        hint: "h", category: "lectura"), in: dir, maxBytes: 300)
        }
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(AutoLog.rotatedName).path))
        let size = (try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(AutoLog.fileName).path)[.size] as? Int) ?? 0
        #expect(size < 300 + 200)
    }

    // MARK: - Session grants

    @Test func aGrantPassesWhatItCoversAndLogsIt() throws {
        let home = try Home()
        #expect(home.grant("ses-a"))
        let out = try home.run(bash("python3 x.py", session: "ses-a"))
        #expect(out["verdict"] as? String == "pass")
        #expect(out["grant"] as? String == "session")
        #expect(out["category"] as? String == "ejecuta")
        #expect(out["critical"] as? Bool == true)
        #expect(out["reason"] as? String == "Auto completo de esta sesión (ejecuta) vía Claude Menu Bar Buddy")
        #expect(out["session_coverable"] as? Bool == true)
        let lines = home.autoLogLines()
        #expect(lines.count == 1)
        let entry = try JSONDecoder().decode(AutoLogEntry.self, from: Data(try #require(lines.first).utf8))
        #expect(entry == AutoLogEntry(ts: entry.ts, agent: "claude", project: "proyX", cwd: "/tmp/proyX",
                                      tool: "Bash", hint: "python3 x.py", category: "ejecuta",
                                      grant: "session", session: "ses-a"))
    }

    /// The grant belongs to a session, not to a folder.
    @Test func anotherSessionInTheSameFolderGetsACard() throws {
        let home = try Home()
        #expect(home.grant("ses-a"))
        let out = try home.run(bash("python3 x.py", session: "ses-b"))
        #expect(out["verdict"] as? String == "card")
        #expect(out["grant"] is NSNull)
        #expect(out["reason"] as? String == "ejecuta código: python3")
        #expect(home.autoLogLines().isEmpty)
    }

    @Test func noUsableSessionIDGetsACard() throws {
        let home = try Home()
        #expect(home.grant("ses-a"))
        #expect(try home.run(bash("python3 x.py"))["verdict"] as? String == "card")
        #expect(try home.run(bash("python3 x.py", session: ""))["verdict"] as? String == "card")
        var numeric = bash("python3 x.py")
        numeric["session_id"] = 42
        #expect(try home.run(numeric)["verdict"] as? String == "card")
    }

    @Test func anExpiredGrantGetsACardAndIsNotDeleted() throws {
        let home = try Home()
        #expect(home.grant("ses-a", at: Date().addingTimeInterval(-(8 * 3600 + 1))))
        let out = try home.run(bash("python3 x.py", session: "ses-a"))
        #expect(out["verdict"] as? String == "card")
        // buddy-rule only deletes on session-end; the app sweeps the expired.
        #expect(FileManager.default.fileExists(atPath: home.grantFile("ses-a").path))
    }

    /// What a grant holds back says so on the card, and goes back to the
    /// agent's prompt when nobody answers.
    @Test func aHeldRequestWithAGrantCardsWithTheHold() throws {
        let home = try Home()
        #expect(home.grant("ses-a"))
        let push = try home.run(bash("git push", session: "ses-a"))
        #expect(push["verdict"] as? String == "card")
        #expect(push["grant"] is NSNull)
        #expect(push["category"] as? String == "sale")
        #expect(push["reason"] as? String == "sale de tu máquina: git push")
        #expect(push["ask_on_timeout"] as? Bool == true)
        #expect(push["session_coverable"] as? Bool == false)
        // The louder neighbour keeps the category; the card names what is held.
        let mixed = try home.run(bash("rm -rf build; git push", session: "ses-a"))
        #expect(mixed["category"] as? String == "irreversible")
        #expect(mixed["reason"] as? String == "sale de tu máquina: git push")
        #expect(mixed["ask_on_timeout"] as? Bool == true)
        #expect(mixed["session_coverable"] as? Bool == false)
        // Without a grant the same line keeps today's reason.
        let today = try home.run(bash("rm -rf build; git push", session: "ses-b"))
        #expect(today["reason"] as? String == "no se puede deshacer: rm")
    }

    @Test func coverableIsComputedWithoutAGrant() throws {
        let home = try Home()
        let python = try home.run(bash("python3 x.py", session: "ses-a"))
        #expect(python["verdict"] as? String == "card")
        #expect(python["session_coverable"] as? Bool == true)
        #expect(python["ask_on_timeout"] as? Bool == true)
        let read = try home.run(bash("git status", session: "ses-a"))
        #expect(read["session_coverable"] as? Bool == true)
        #expect(read["ask_on_timeout"] as? Bool == false)
        let push = try home.run(bash("git push", session: "ses-a"))
        #expect(push["session_coverable"] as? Bool == false)
        #expect(push["ask_on_timeout"] as? Bool == true)
        let question = try home.run(["tool_name": "AskUserQuestion", "tool_input": [:], "cwd": "/tmp", "session_id": "ses-a"])
        #expect(question["session_coverable"] as? Bool == false)
        #expect(question["ask_on_timeout"] as? Bool == false)
        let mcp = try home.run(["tool_name": "mcp__notas__crear", "tool_input": [:], "cwd": "/tmp", "session_id": "ses-a"])
        #expect(mcp["session_coverable"] as? Bool == false)
    }

    @Test func planModeWithAGrantDefers() throws {
        let home = try Home()
        #expect(home.grant("ses-a"))
        let out = try home.run(bash("python3 x.py", plan: true, session: "ses-a"))
        #expect(out["verdict"] as? String == "defer")
        #expect(out["grant"] is NSNull)
        #expect(home.autoLogLines().isEmpty)
    }

    /// "session" marks only what passed thanks to the grant.
    @Test func autoModeAndAlwaysAllowKeepTheirLabelUnderAGrant() throws {
        let auto = try Home(autoMode: true)
        #expect(auto.grant("ses-a"))
        let read = try auto.run(bash("git status", session: "ses-a"))
        #expect(read["grant"] as? String == "auto")
        #expect((read["reason"] as? String ?? "").contains("Modo auto (lectura)"))
        let first = try #require(auto.autoLogLines().first)
        let entry = try JSONDecoder().decode(AutoLogEntry.self, from: Data(first.utf8))
        #expect(entry.grant == "auto")
        #expect(entry.session == "ses-a")
        // An id that isn't valid is not copied into the log.
        _ = try auto.run(bash("git status", session: "a/b"))
        #expect(auto.autoLogLines().count == 2)
        let last = try #require(auto.autoLogLines().last)
        let second = try JSONDecoder().decode(AutoLogEntry.self, from: Data(last.utf8))
        #expect(second.session == nil)

        let always = try Home(allowlist: #"{"global":["git"],"projects":{}}"#)
        #expect(always.grant("ses-a"))
        #expect(try always.run(bash("git status", session: "ses-a"))["grant"] as? String == "always")
    }

    @Test func theAgentsWebPassesUnderAGrant() throws {
        let home = try Home()
        #expect(home.grant("ses-a", cwd: "/tmp"))
        let out = try home.run(["tool_name": "WebFetch", "tool_input": ["url": "https://x"], "cwd": "/tmp", "session_id": "ses-a"])
        #expect(out["verdict"] as? String == "pass")
        #expect(out["grant"] as? String == "session")
    }

    /// Live capture: a subagent's hook carries its parent's session_id, so
    /// the parent's grant covers it.
    @Test func aSubagentIsCoveredByItsSessionsGrant() throws {
        let home = try Home()
        #expect(home.grant("e575efb6-a7ad-4a1e-ab95-e32b6755393f", cwd: "/tmp/p"))
        let out = try home.runRaw(ClaudeHookFixtures.preToolUseSubagent)
        #expect(out["verdict"] as? String == "pass")
        #expect(out["grant"] as? String == "session")
        let line = try #require(home.autoLogLines().first)
        let entry = try JSONDecoder().decode(AutoLogEntry.self, from: Data(line.utf8))
        #expect(entry.session == "e575efb6-a7ad-4a1e-ab95-e32b6755393f")
    }

    @Test func anyRequestOfTheSessionRenewsItsGrant() throws {
        let home = try Home()
        #expect(home.grant("ses-a", at: Date().addingTimeInterval(-120)))
        #expect(home.grant("ses-b", at: Date().addingTimeInterval(-120)))
        _ = try home.run(bash("git push", session: "ses-a"))   // a card is activity too
        #expect(Date().timeIntervalSince(home.lastActivity("ses-a") ?? .distantPast) < 60)
        #expect(Date().timeIntervalSince(home.lastActivity("ses-b") ?? .distantFuture) > 100)
    }

    /// buddy-rule and the app's queue sweep give the same reason, from one place.
    @Test func sessionGrantReasonIsFixed() {
        #expect(AutoModePolicy.sessionGrantReason(category: .ejecuta)
                == "Auto completo de esta sesión (ejecuta) vía Claude Menu Bar Buddy")
        #expect(AutoModePolicy.sessionGrantReason(category: .cambioLocal)
                == "Auto completo de esta sesión (cambio_local) vía Claude Menu Bar Buddy")
    }

    @Test func askOnTimeoutIsCriticalOrHeldUnderAGrant() {
        let held = Assessment(.desconocido, "la regla no reconoce: x", sessionHold: "retenido: x")
        #expect(HookRuleCLI.asksOnTimeout(held, grantLive: true))
        #expect(!HookRuleCLI.asksOnTimeout(held, grantLive: false))
        #expect(!HookRuleCLI.asksOnTimeout(Assessment(.lectura, "solo lee"), grantLive: true))
        #expect(HookRuleCLI.asksOnTimeout(Assessment(.ejecuta, "ejecuta código: python3"), grantLive: false))
        #expect(HookRuleCLI.asksOnTimeout(Assessment(.sale, "sale de tu máquina: git push"), grantLive: true))
    }

    @Test(arguments: ["", "{not json", "[1,2]"])
    func invalidInputAsksOnTimeout(text: String) throws {
        let out = HookRuleCLI.run(input: Data(text.utf8), environment: ["HOME": "/nonexistent"])
        let obj = try JSONSerialization.jsonObject(with: out) as! [String: Any]
        #expect(obj["ask_on_timeout"] as? Bool == true)
        #expect(obj["session_coverable"] as? Bool == false)
    }

    // MARK: - session-end

    @Test func sessionEndRevokesOnlyItsOwnGrantAndLogsIt() throws {
        let home = try Home()
        let id = "d1538fa3-1006-4201-924b-8dafae43ffe3"
        #expect(home.grant(id, cwd: "/tmp/p"))
        #expect(home.grant("ses-b"))
        #expect(home.grant(id, agent: "opencode", cwd: "/tmp/p"))
        #expect(home.sessionEnd(ClaudeHookFixtures.sessionEnd) == "{}")
        #expect(!FileManager.default.fileExists(atPath: home.grantFile(id).path))
        #expect(FileManager.default.fileExists(atPath: home.grantFile("ses-b").path))
        #expect(FileManager.default.fileExists(atPath: home.grantFile(id, agent: "opencode").path))
        let lines = home.autoLogLines()
        #expect(lines.count == 1)
        let entry = try JSONDecoder().decode(AutoLogEntry.self, from: Data(try #require(lines.first).utf8))
        #expect(entry == AutoLogEntry(ts: entry.ts, agent: "claude", project: "p", cwd: "/tmp/p", tool: "sesión",
                                      hint: "apagada: fin de sesión", category: "concesion",
                                      grant: "concesion", session: id))
    }

    @Test func sessionEndWithNothingToRevokeOnlyAnswers() throws {
        let home = try Home()
        #expect(home.grant("ses-b"))
        for text in [ClaudeHookFixtures.sessionEnd, #"{"session_id":"../x"}"#, #"{"session_id":7}"#, "{}", "no es json", ""] {
            #expect(home.sessionEnd(text) == "{}", "input: \(text)")
        }
        #expect(home.autoLogLines().isEmpty)
        #expect(FileManager.default.fileExists(atPath: home.grantFile("ses-b").path))
    }
}
