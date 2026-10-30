import Testing
import BuddyCore

@Suite struct OpenCodeRuleTests {
    private let dir = "/Users/u/repo"
    private func req(_ action: String, _ resources: [String], files: [String] = [], callID: String? = nil) -> OpenCodePermissionRequest {
        OpenCodePermissionRequest(id: "per_x", sessionID: "ses_x", action: action, resources: resources,
                                  editedFiles: files, patches: [], callID: callID)
    }

    @Test func shellPrefersTheFullCommand() {
        let s = OpenCodeRule.subjects(for: req("shell", ["ls -la", "rm x"]), toolInput: ["command": "ls -la && rm x"], directory: dir)
        #expect(s == [.shell(command: "ls -la && rm x")])
    }

    @Test func shellFallsBackToTheResources() {
        #expect(OpenCodeRule.subjects(for: req("shell", ["ls -la", "rm x"]), toolInput: nil, directory: dir)
                == [.shell(command: "ls -la; rm x")])
    }

    @Test func editResolvesRelativeFilesAgainstTheSession() {
        #expect(OpenCodeRule.subjects(for: req("edit", ["notas.txt"], files: ["notas.txt"]), toolInput: nil, directory: dir)
                == [.fileEdit(path: "/Users/u/repo/notas.txt")])
        #expect(OpenCodeRule.subjects(for: req("edit", ["a"]), toolInput: ["path": "/Users/u/repo/a.swift"], directory: dir)
                == [.fileEdit(path: "/Users/u/repo/a.swift")])
    }

    @Test func otherActions() {
        #expect(OpenCodeRule.subjects(for: req("read", [".env"]), toolInput: nil, directory: dir) == [.fileRead(path: "/Users/u/repo/.env")])
        #expect(OpenCodeRule.subjects(for: req("webfetch", ["https://x"]), toolInput: nil, directory: dir) == [.web(tool: "webfetch")])
        #expect(OpenCodeRule.subjects(for: req("skill", ["x"]), toolInput: nil, directory: dir) == [.other(tool: "skill")])
    }

    @Test func worstFileWins() {
        let r = OpenCodeRule.assess(req("edit", [], files: ["src/a.swift", ".git/config", "b.md"]), toolInput: nil,
                                    directory: dir, context: ruleContext)
        #expect(r.assessment.category == .rutaProtegida)
        #expect(r.subject == .fileEdit(path: "/Users/u/repo/.git/config"))
    }

    @Test func assessments() {
        let a = { (r: OpenCodePermissionRequest, input: [String: String]?) in
            OpenCodeRule.assess(r, toolInput: input, directory: self.dir, context: ruleContext).assessment.category
        }
        #expect(a(req("shell", ["git status"]), nil) == .lectura)
        #expect(a(req("shell", ["x"]), ["command": "python3 x.py"]) == .ejecuta)
        #expect(a(req("edit", ["src/a.swift"]), nil) == .edicion)
        #expect(a(req("read", [".env"]), nil) == .sensible)
        #expect(a(req("read", ["src/a.swift"]), nil) == .lectura)
        #expect(a(req("websearch", ["q"]), nil) == .sale)
        #expect(a(req("external_directory", ["/etc/*"]), nil) == .desconocido)
    }

    @Test func fileReadInCommandRule() {
        #expect(CommandRule.assess(.fileRead(path: "notes.txt"), context: ruleContext)
                == Assessment(.desconocido, "no se puede saber qué lee: notes.txt"))
        #expect(CommandRule.assess(.fileRead(path: "/Users/u/.aws/credentials"), context: ruleContext).category == .sensible)
        #expect(CommandRule.assess(.fileRead(path: "/Users/u/repo/a.swift"), context: ruleContext) == Assessment(.lectura, "solo lee"))
    }
}
