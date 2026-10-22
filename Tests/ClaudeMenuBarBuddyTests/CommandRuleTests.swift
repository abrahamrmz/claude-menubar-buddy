import Testing
import BuddyCore

@Suite struct CommandRuleTests {
    @Test func mapsClaudeTools() {
        #expect(RuleSubject.fromClaudeHook(toolName: "Bash", toolInput: ["command": "ls"]) == .shell(command: "ls"))
        #expect(RuleSubject.fromClaudeHook(toolName: "Edit", toolInput: ["file_path": "/a"]) == .fileEdit(path: "/a"))
        #expect(RuleSubject.fromClaudeHook(toolName: "MultiEdit", toolInput: ["file_path": "/a"]) == .fileEdit(path: "/a"))
        #expect(RuleSubject.fromClaudeHook(toolName: "Write", toolInput: ["file_path": "/a"]) == .fileEdit(path: "/a"))
        #expect(RuleSubject.fromClaudeHook(toolName: "NotebookEdit", toolInput: ["notebook_path": "/n"]) == .fileEdit(path: "/n"))
        #expect(RuleSubject.fromClaudeHook(toolName: "WebFetch", toolInput: [:]) == .web(tool: "WebFetch"))
        #expect(RuleSubject.fromClaudeHook(toolName: "WebSearch", toolInput: [:]) == .web(tool: "WebSearch"))
        #expect(RuleSubject.fromClaudeHook(toolName: "AskUserQuestion", toolInput: [:]) == .question(tool: "AskUserQuestion"))
        #expect(RuleSubject.fromClaudeHook(toolName: "ExitPlanMode", toolInput: [:]) == .question(tool: "ExitPlanMode"))
        #expect(RuleSubject.fromClaudeHook(toolName: "Bash", toolInput: [:]) == .shell(command: ""))
        #expect(RuleSubject.fromClaudeHook(toolName: "Mystery", toolInput: [:]) == .other(tool: "Mystery"))
    }

    @Test func assessesNonShellSubjects() {
        let a = { CommandRule.assess($0, context: ruleContext) }
        #expect(a(.fileEdit(path: "/Users/u/repo/x.swift")) == Assessment(.edicion, "edición de archivo"))
        #expect(a(.fileEdit(path: "/Users/u/.zshrc")).category == .rutaProtegida)
        #expect(a(.fileEdit(path: "/Users/u/repo/.env")).category == .sensible)
        #expect(a(.fileEdit(path: "notes.txt")) == Assessment(.desconocido, "no se puede saber dónde cae: notes.txt"))
        #expect(a(.fileEdit(path: "/tmp/p/../../etc/passwd")).category == .desconocido)
        #expect(a(.fileEdit(path: "")).category == .desconocido)
        #expect(a(.web(tool: "WebFetch")) == Assessment(.sale, "sale de tu máquina: WebFetch"))
        #expect(a(.question(tool: "AskUserQuestion")) == Assessment(.pregunta, "pregunta del agente"))
        #expect(a(.question(tool: "ExitPlanMode")) == Assessment(.pregunta, "plan propuesto"))
        #expect(a(.other(tool: "Mystery")) == Assessment(.desconocido, "la regla no reconoce: Mystery"))
        #expect(a(.shell(command: "python3 x.py")).category == .ejecuta)
    }

    private func decide(_ subject: RuleSubject, auto: Bool, allow: AlwaysAllow = AlwaysAllow(),
                        cwd: String? = "/Users/u/repo", plan: Bool = false) -> RuleDecision {
        AutoModePolicy.decide(subject: subject, assessment: CommandRule.assess(subject, context: ruleContext),
                              autoMode: auto, allowList: allow, cwd: cwd, planMode: plan)
    }

    @Test func autoModePassesRoutineWork() {
        let d = decide(.shell(command: "git status"), auto: true)
        #expect(d.verdict == .pass)
        #expect(d.grant == .auto)
        #expect(decide(.fileEdit(path: "/Users/u/repo/x.swift"), auto: true).verdict == .pass)
        #expect(decide(.shell(command: "mkdir out"), auto: true).verdict == .pass)
    }

    @Test func autoModeOffCardsEverything() {
        #expect(decide(.shell(command: "git status"), auto: false).verdict == .card)
        #expect(decide(.fileEdit(path: "/Users/u/repo/x.swift"), auto: false).verdict == .card)
    }

    @Test func criticalAndUnknownAlwaysCard() {
        for s: RuleSubject in [.shell(command: "python3 x.py"), .shell(command: "mytool"), .web(tool: "WebFetch"),
                               .fileEdit(path: "/Users/u/.zshrc"), .question(tool: "AskUserQuestion")] {
            #expect(decide(s, auto: true).verdict == .card, "\(s)")
        }
    }

    @Test func planModeDefersInsteadOfGranting() {
        let d = decide(.fileEdit(path: "/Users/u/repo/x.swift"), auto: true, plan: true)
        #expect(d.verdict == .deferToAgent)
        #expect(d.grant == nil)
        #expect(decide(.shell(command: "python3 x.py"), auto: true, plan: true).verdict == .card)
    }

    @Test func alwaysAllowGrantsNonCriticalSingleCommands() {
        let global = decide(.shell(command: "mytool --run"), auto: false, allow: AlwaysAllow(global: ["mytool"]))
        #expect(global.verdict == .pass)
        #expect(global.grant == .always)
        #expect(global.grantScope == "everywhere")
        #expect(global.base == "mytool")
        let project = decide(.shell(command: "mytool"), auto: false,
                             allow: AlwaysAllow(projects: ["/Users/u/repo": ["mytool"]]))
        #expect(project.grantScope == "in this project")
        #expect(decide(.shell(command: "mytool"), auto: false, allow: AlwaysAllow(projects: ["/Users/u/repo": ["mytool"]]),
                       cwd: "/Users/u/otro").verdict == .card)
    }

    @Test func alwaysAllowNeverGrantsCritical() {
        #expect(decide(.shell(command: "npm test"), auto: false, allow: AlwaysAllow(global: ["npm"])).verdict == .card)
        #expect(decide(.shell(command: "git push"), auto: true, allow: AlwaysAllow(global: ["git"])).verdict == .card)
        #expect(decide(.shell(command: "python3 x.py"), auto: true, allow: AlwaysAllow(global: ["python3"])).verdict == .card)
    }
}
