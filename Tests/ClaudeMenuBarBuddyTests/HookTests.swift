import Foundation
import Testing

// Fixture harness for the REAL hook.sh — the piece that decides what runs
// without a card, exercised end-to-end: request JSON in on stdin, decision
// JSON out on stdout, with the response files written the way the app writes
// them. Each run gets its own $HOME (so the config dir, the allowlist and
// the auto-edits flag are fixtures, not the user's), and a pgrep shim on
// $PATH plays the part of the app being (or not being) up.
//
// The metacharacter cases are the ones a refactor would break silently:
// `;` `|` `$` etc. must send a command to the card REGARDLESS of its first
// word, or "always allow git" quietly becomes "always allow everything".
struct HookTests {
    private static let hookScript = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("hook.sh")

    // MARK: - Harness

    private struct HookRun {
        let stdout: String
        /// The request file's JSON, if the hook fell through to the card.
        let request: [String: Any]?
        var cardShown: Bool { request != nil }
        var decision: [String: Any]? {
            guard let data = stdout.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return (obj["hookSpecificOutput"] as? [String: Any]) ?? obj
        }
    }

    /// One throwaway $HOME per run — tests run in parallel, and the real
    /// buddy may well be running on this machine while they do.
    private struct Harness {
        let home: URL
        var configDir: URL { home.appendingPathComponent(".config/claude-menubar-buddy") }

        init(allowlist: String? = nil, autoEdits: Bool = false) throws {
            home = FileManager.default.temporaryDirectory
                .appendingPathComponent("buddy-hook-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            if let allowlist = allowlist {
                try allowlist.write(to: configDir.appendingPathComponent("always_allow.json"),
                                    atomically: true, encoding: .utf8)
            }
            if autoEdits {
                try Data().write(to: configDir.appendingPathComponent("auto_approve_edits"))
            }
        }

        func cleanup() { try? FileManager.default.removeItem(at: home) }

        func firstRequestFile() throws -> URL? {
            try FileManager.default.contentsOfDirectory(at: configDir, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("request_") && $0.pathExtension == "json" }
        }

        /// Runs hook.sh with `input` on stdin. If a request file appears (the
        /// card path), `respond` is written as the app would write its
        /// response file; with no `respond`, the hook gets SIGTERM — the same
        /// signal Claude Code sends when the user answers in the terminal.
        func run(_ input: [String: Any],
                 appRunning: Bool = true,
                 respond: [String: Any]? = nil) throws -> HookRun {
            // The pgrep shim: "is the app up" is a fixture, not a fact
            // about this machine.
            let shimDir = home.appendingPathComponent("bin")
            try FileManager.default.createDirectory(at: shimDir, withIntermediateDirectories: true)
            let shim = shimDir.appendingPathComponent("pgrep")
            try "#!/bin/sh\nexit \(appRunning ? 0 : 1)\n"
                .write(to: shim, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: shim.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [HookTests.hookScript.path]
            process.environment = [
                "HOME": home.path,
                "PATH": "\(shimDir.path):/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            ]
            let stdinPipe = Pipe(), stdoutPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            try process.run()
            let inputData = try JSONSerialization.data(withJSONObject: input)
            stdinPipe.fileHandleForWriting.write(inputData)
            stdinPipe.fileHandleForWriting.closeFile()

            var request: [String: Any]?
            let deadline = Date().addingTimeInterval(15)
            while process.isRunning && Date() < deadline {
                if request == nil, let file = try firstRequestFile() {
                    // `jq > file` creates the file an instant before filling
                    // it — an empty or partial read means "not written yet",
                    // not "broken"; the next tick gets the whole thing.
                    guard let data = try? Data(contentsOf: file),
                          let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else {
                        usleep(10_000)
                        continue
                    }
                    request = parsed
                    let id = file.lastPathComponent
                        .replacingOccurrences(of: "request_", with: "")
                        .replacingOccurrences(of: ".json", with: "")
                    if let respond = respond {
                        let data = try JSONSerialization.data(withJSONObject: respond)
                        try data.write(to: configDir.appendingPathComponent("response_\(id).json"))
                    } else {
                        process.terminate()
                    }
                }
                usleep(30_000)
            }
            if process.isRunning {
                process.terminate()
                Issue.record("hook.sh did not exit within 15s")
            }
            process.waitUntilExit()
            let output = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            return HookRun(stdout: output.trimmingCharacters(in: .whitespacesAndNewlines),
                           request: request)
        }
    }

    private func bash(_ command: String, cwd: String = "/tmp/proyX") -> [String: Any] {
        ["tool_name": "Bash", "tool_input": ["command": command], "cwd": cwd]
    }

    private func edit(_ path: String) -> [String: Any] {
        ["tool_name": "Edit",
         "tool_input": ["file_path": path, "old_string": "a", "new_string": "b"],
         "cwd": "/tmp/proyX"]
    }

    private func assertAllowed(_ run: HookRun, reasonContains: String,
                               sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(run.decision?["permissionDecision"] as? String == "allow",
                "expected allow, got: \(run.stdout)", sourceLocation: sourceLocation)
        let reason = run.decision?["permissionDecisionReason"] as? String ?? ""
        #expect(reason.contains(reasonContains),
                "reason \"\(reason)\" missing \"\(reasonContains)\"", sourceLocation: sourceLocation)
    }

    // MARK: - Nobody home

    /// With the app not running there is no icon announcing any grant, so no
    /// grant may be applied: straight to the native prompt, no request file.
    @Test func noAppMeansNativePromptEvenWithGrants() throws {
        let h = try Harness(allowlist: #"{"global":["git"],"projects":{}}"#, autoEdits: true)
        defer { h.cleanup() }
        let run = try h.run(bash("git status"), appRunning: false)
        #expect(run.stdout == "{}")
        #expect(!run.cardShown)
    }

    // MARK: - Always-allow fast path

    @Test func globalGrantAllowsInstantly() throws {
        let h = try Harness(allowlist: #"{"global":["git"],"projects":{}}"#)
        defer { h.cleanup() }
        let run = try h.run(bash("git status"))
        assertAllowed(run, reasonContains: "everywhere")
        #expect(!run.cardShown)
    }

    /// The pre-scopes shape of the file — a bare array — reads as global.
    @Test func legacyBareArrayReadsAsGlobal() throws {
        let h = try Harness(allowlist: #"["ls"]"#)
        defer { h.cleanup() }
        assertAllowed(try h.run(bash("ls -la")), reasonContains: "everywhere")
    }

    /// An env assignment prefix disqualifies the fast path. The first word
    /// still reads `git`, but the assignment decides what that word resolves
    /// to — which is the same failure the metacharacter screen exists to
    /// prevent, just spelled without any metacharacter.
    @Test(arguments: [
        "FOO=bar BAZ_2=x git status",              // harmless-looking, same shape
        "PATH=/tmp/evil git status",               // picks a different binary
        "DYLD_INSERT_LIBRARIES=/tmp/x.dylib git status",  // foreign code in the real one
        "GIT_SSH_COMMAND=/tmp/evil.sh git fetch",  // git's own exec hook
    ])
    func envAssignmentPrefixGetsACard(command: String) throws {
        let h = try Harness(allowlist: #"{"global":["git"],"projects":{}}"#)
        defer { h.cleanup() }
        let run = try h.run(bash(command))
        #expect(run.cardShown, "fast-pathed past the card: \(command)")
        #expect(run.stdout.isEmpty, "emitted a decision for: \(command)")
    }

    @Test func projectGrantOnlySpeaksForItsProject() throws {
        let h = try Harness(allowlist: #"{"global":[],"projects":{"/tmp/proyX":["npm"]}}"#)
        defer { h.cleanup() }
        assertAllowed(try h.run(bash("npm test", cwd: "/tmp/proyX")),
                      reasonContains: "in this project")
    }

    @Test func projectGrantIsSilentElsewhere() throws {
        let h = try Harness(allowlist: #"{"global":[],"projects":{"/tmp/proyX":["npm"]}}"#)
        defer { h.cleanup() }
        let elsewhere = try h.run(bash("npm test", cwd: "/tmp/otro"))
        #expect(elsewhere.cardShown)
        #expect(elsewhere.stdout.isEmpty)
    }

    /// An exact-path match, not a prefix: a grant on /repo must not cover
    /// /repo-secrets.
    @Test func projectGrantDoesNotPrefixMatch() throws {
        let h = try Harness(allowlist: #"{"global":[],"projects":{"/tmp/repo":["npm"]}}"#)
        defer { h.cleanup() }
        #expect(try h.run(bash("npm test", cwd: "/tmp/repo-secrets")).cardShown)
    }

    /// THE security property: any shell metacharacter means the first word
    /// has stopped describing what runs, so the grant may not speak — the
    /// card appears no matter how boring the base command looks.
    @Test(arguments: [
        "echo hi ; rm -rf ~",
        "git status && rm -rf ~",
        "git status | tee /tmp/x",
        "git status > /tmp/x",
        "git status < /tmp/x",
        "git $(whoami)",
        "git `id`",
        "git status & sleep 1",
        "echo (subshell)",
        "git status \\",
        "echo hi\nrm -rf ~",
        "echo $HOME",
    ])
    func metacharactersAlwaysGetACard(command: String) throws {
        let h = try Harness(allowlist: #"{"global":["git","echo"],"projects":{}}"#)
        defer { h.cleanup() }
        let run = try h.run(bash(command))
        #expect(run.cardShown, "fast-pathed past the card: \(command.debugDescription)")
        #expect(run.stdout.isEmpty, "emitted a decision for: \(command.debugDescription)")
    }

    @Test func unlistedCommandGetsACard() throws {
        let h = try Harness(allowlist: #"{"global":["git"],"projects":{}}"#)
        defer { h.cleanup() }
        #expect(try h.run(bash("curl https://example.com")).cardShown)
    }

    // MARK: - Auto-approve edits

    @Test func autoEditsAllowsAPlainFile() throws {
        let h = try Harness(autoEdits: true)
        defer { h.cleanup() }
        let run = try h.run(edit("/tmp/proyX/notes.txt"))
        assertAllowed(run, reasonContains: "Auto-approved edit")
        #expect(!run.cardShown)
    }

    /// The files that decide what runs on this machine tomorrow always get a
    /// card — including the buddy's own config, so an auto-approved Write
    /// can't widen the very grant that let it through. ~HOME~ is replaced
    /// with the harness's home, since these guards match against $HOME.
    @Test(arguments: [
        "~HOME~/.ssh/config",
        "~HOME~/.gnupg/gpg.conf",
        "~HOME~/.claude/settings.json",
        "~HOME~/.config/claude-menubar-buddy/always_allow.json",
        "~HOME~/Library/LaunchAgents/evil.plist",
        "~HOME~/Library/Application Support/Claude/plan-usage-history.json",
        "~HOME~/.zshrc",
        "/tmp/proyX/.git/hooks/pre-commit",
        "/etc/hosts",
        "/Library/LaunchDaemons/evil.plist",
        "notes.txt",                    // relative: can't tell where it lands
        "/tmp/proyX/../../etc/passwd",  // .. : same
        // A project's own settings can register hooks — an auto-approved
        // write here would run code on the next tool call, turning this
        // grant into a wider one.
        "/tmp/proyX/.claude/settings.json",
        "/tmp/proyX/.claude/settings.local.json",
        // core.fsmonitor / core.pager / an `!` alias: execution on the next
        // git command, without ever touching .git/hooks.
        "/tmp/proyX/.git/config",
        "/tmp/proyX/.envrc",            // direnv runs it on the next cd
        "/tmp/proyX/.vscode/tasks.json",  // can run on folderOpen
        "~HOME~/.gitconfig",
        "~HOME~/.oh-my-zsh/custom/evil.zsh",
        "~HOME~/.zlogin",
        "~HOME~/.bash_login",
        "~HOME~/.config/fish/config.fish",
        "/private/etc/hosts",           // /etc through its real path
    ])
    func autoEditsStopsAtProtectedPaths(path: String) throws {
        let h = try Harness(autoEdits: true)
        defer { h.cleanup() }
        let resolved = path.replacingOccurrences(of: "~HOME~", with: h.home.path)
        let run = try h.run(edit(resolved))
        #expect(run.cardShown, "auto-approved a protected path: \(resolved)")
    }

    /// The flag only covers file-editing tools — Bash with the flag up still
    /// gets its card.
    @Test func autoEditsDoesNotCoverBash() throws {
        let h = try Harness(autoEdits: true)
        defer { h.cleanup() }
        #expect(try h.run(bash("rm -rf /tmp/x")).cardShown)
    }

    // MARK: - AskUserQuestion

    /// Multi-select needs an interaction the card doesn't have: straight to
    /// the native picker, no card that can only express part of the answer.
    @Test func multiSelectBypassesTheCard() throws {
        let h = try Harness()
        defer { h.cleanup() }
        let input: [String: Any] = [
            "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [
                ["question": "¿Cuáles?", "multiSelect": true,
                 "options": [["label": "a"], ["label": "b"]]],
            ]],
            "cwd": "/tmp/proyX",
        ]
        let run = try h.run(input)
        #expect(run.stdout == "{}")
        #expect(!run.cardShown)
    }

    /// Single-select rides to the card, and the answer comes back through
    /// the tool's own `answers` field via updatedInput — Claude receives an
    /// ordinary result, not a blocked tool.
    @Test func answerInjectsIntoUpdatedInput() throws {
        let h = try Harness()
        defer { h.cleanup() }
        let input: [String: Any] = [
            "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [
                ["question": "¿Color?", "multiSelect": false,
                 "options": [["label": "azul"], ["label": "rojo"]]],
            ]],
            "cwd": "/tmp/proyX",
        ]
        let run = try h.run(input, respond: ["decision": "answer",
                                             "answers": ["¿Color?": "azul"]])
        #expect(run.decision?["permissionDecision"] as? String == "allow")
        let updated = run.decision?["updatedInput"] as? [String: Any]
        let answers = updated?["answers"] as? [String: String]
        #expect(answers?["¿Color?"] == "azul")
        // The card knew what it was asking: the questions rode along.
        #expect(run.request?["choices"] != nil)
    }

    // MARK: - Card round-trips

    @Test func allowRoundTrip() throws {
        let h = try Harness()
        defer { h.cleanup() }
        let run = try h.run(bash("rm -rf /tmp/x"), respond: ["decision": "allow"])
        assertAllowed(run, reasonContains: "Approved via Claude Menu Bar Buddy")
        // Answered request files must not linger for the app to re-show.
        #expect(try h.firstRequestFile() == nil)
        // The request carried what the card needs to say what's being asked.
        #expect(run.request?["tool"] as? String == "Bash")
        #expect(run.request?["hint"] as? String == "rm -rf /tmp/x")
        #expect(run.request?["project"] as? String == "proyX")
    }

    @Test func denyRoundTripCarriesTheReason() throws {
        let h = try Harness()
        defer { h.cleanup() }
        let run = try h.run(bash("rm -rf /tmp/x"),
                            respond: ["decision": "deny", "reason": "keep planning: falta X"])
        #expect(run.decision?["permissionDecision"] as? String == "deny")
        #expect(run.decision?["permissionDecisionReason"] as? String == "keep planning: falta X")
    }

    /// "pass" = hand off to the native prompt right now (the ↗ button).
    @Test func passHandsOffToNativePrompt() throws {
        let h = try Harness()
        defer { h.cleanup() }
        let run = try h.run(bash("rm -rf /tmp/x"), respond: ["decision": "pass"])
        #expect(run.stdout == "{}")
    }

    /// SIGTERM (the user answered in the terminal) must clean up the request
    /// file so the app doesn't keep showing an already-resolved request.
    @Test func termCleansUpTheRequestFile() throws {
        let h = try Harness()
        defer { h.cleanup() }
        let run = try h.run(bash("rm -rf /tmp/x"))  // no respond → harness TERMs
        #expect(run.cardShown)
        #expect(try h.firstRequestFile() == nil)
    }
}
