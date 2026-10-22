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
    }

    private func bash(_ c: String, plan: Bool = false) -> [String: Any] {
        var i: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": c], "cwd": "/tmp/proyX"]
        if plan { i["permission_mode"] = "plan" }
        return i
    }

    @Test func outputHasExactlyTheContractKeys() throws {
        let out = try Home().run(bash("git status"))
        #expect(Set(out.keys) == ["verdict", "category", "critical", "reason", "grant"])
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
}
