import Testing
import BuddyCore

/// Spec 5.1 (what a session grant covers) and 5.4 (where it sits in the policy).
@Suite struct SessionGrantPolicyTests {
    private func covers(_ subject: RuleSubject) -> Bool {
        AutoModePolicy.sessionGrantCovers(subject: subject, assessment: CommandRule.assess(subject, context: ruleContext))
    }

    private func decide(_ subject: RuleSubject, auto: Bool = false, grant: Bool = true,
                        allow: AlwaysAllow = AlwaysAllow(), plan: Bool = false) -> RuleDecision {
        AutoModePolicy.decide(subject: subject, assessment: CommandRule.assess(subject, context: ruleContext),
                              autoMode: auto, allowList: allow, cwd: "/Users/u/repo", planMode: plan, sessionGrant: grant)
    }

    // Table 5.1, shell: every local category passes unless held.
    @Test(arguments: [
        "cat a.txt", "mkdir out", "echo x > ~/Documents/a.txt", "python3 x.py", "rm -rf build", "cat .env",
        "mytool --run", "git reset --hard", "swift build && swift test",
    ])
    func shellThatStaysHere(command: String) { #expect(covers(.shell(command: command)), "\(command)") }

    @Test(arguments: [
        "git push", "curl https://x", "echo x >> ~/.zshrc", "git config core.hooksPath .h", "sudo ls",
        "rm -rf build; git push", "npm publish", "bash -c 'git push'",
    ])
    func shellThatLeavesOrIsHeld(command: String) { #expect(!covers(.shell(command: command)), "\(command)") }

    @Test func fileEdits() {
        #expect(covers(.fileEdit(path: "/Users/u/repo/x.swift")))
        #expect(covers(.fileEdit(path: "/Users/u/repo/.env")))
        #expect(!covers(.fileEdit(path: "/Users/u/.zshrc")))
        #expect(!covers(.fileEdit(path: "notes.txt")))
        #expect(!covers(.fileEdit(path: "/tmp/p/../../etc/passwd")))
    }

    @Test func readsWebQuestionsAndTheUnknown() {
        #expect(covers(.fileRead(path: "/Users/u/repo/a.swift")))
        #expect(covers(.fileRead(path: "/Users/u/.aws/credentials")))
        #expect(covers(.fileRead(path: "notes.txt")))
        #expect(covers(.web(tool: "WebFetch")))
        #expect(covers(.web(tool: "webfetch")))
        #expect(!covers(.question(tool: "AskUserQuestion")))
        #expect(!covers(.question(tool: "ExitPlanMode")))
        #expect(!covers(.other(tool: "Mystery")))
        #expect(!covers(.other(tool: "external_directory")))
    }

    /// The web is always `.sale` and still passes: the user decided so (spec 4).
    /// A shell line that leaves never does.
    @Test func theWebPassesButPublishingDoesNot() {
        #expect(AutoModePolicy.sessionGrantCovers(subject: .web(tool: "WebFetch"),
                                                  assessment: Assessment(.sale, "sale de tu máquina: WebFetch")))
        #expect(!AutoModePolicy.sessionGrantCovers(subject: .shell(command: "git push"),
                                                   assessment: Assessment(.sale, "sale de tu máquina: git push")))
    }

    @Test func aHeldAssessmentIsNeverCovered() {
        #expect(!AutoModePolicy.sessionGrantCovers(
            subject: .fileEdit(path: "/Users/u/repo/.env"),
            assessment: Assessment(.sensible, "toca un archivo sensible: /Users/u/repo/.env",
                                   sessionHold: "escribe en una ruta protegida: /Users/u/repo/.git/config")))
        #expect(!AutoModePolicy.sessionGrantCovers(subject: .shell(command: "ls"),
                                                   assessment: Assessment(.lectura, "solo lee", sessionHold: "x")))
        #expect(!AutoModePolicy.sessionGrantCovers(subject: .fileRead(path: "/Users/u/repo/a"),
                                                   assessment: Assessment(.lectura, "solo lee", sessionHold: "x")))
    }

    @Test func aGrantPassesWhatItCoversUnderItsOwnLabel() {
        let d = decide(.shell(command: "python3 x.py"))
        #expect(d.verdict == .pass)
        #expect(d.grant == .session)
        #expect(d.grantScope == nil)
        #expect(d.base == nil)
        #expect(decide(.shell(command: "rm -rf build")).grant == .session)
        #expect(decide(.web(tool: "WebFetch")).grant == .session)
        #expect(decide(.fileEdit(path: "/Users/u/repo/.env")).grant == .session)
        #expect(Grant.session.rawValue == "session")
    }

    @Test func aGrantDoesNotNeedAutoMode() {
        #expect(decide(.shell(command: "git status"), auto: false).grant == .session)
        #expect(decide(.fileEdit(path: "/Users/u/repo/x.swift"), auto: false).grant == .session)
    }

    @Test func withoutAGrantNothingChanges() {
        #expect(decide(.shell(command: "python3 x.py"), grant: false).verdict == .card)
        #expect(decide(.web(tool: "WebFetch"), grant: false).verdict == .card)
        let python = RuleSubject.shell(command: "python3 x.py")
        let byDefault = AutoModePolicy.decide(subject: python, assessment: CommandRule.assess(python, context: ruleContext),
                                              autoMode: true, allowList: AlwaysAllow(), cwd: nil, planMode: false)
        #expect(byDefault.verdict == .card)
    }

    @Test func whatIsHeldOrUncoveredStillCards() {
        for subject: RuleSubject in [
            .shell(command: "git push"), .shell(command: "rm -rf build; git push"), .shell(command: "sudo ls"),
            .fileEdit(path: "/Users/u/.zshrc"), .question(tool: "AskUserQuestion"), .question(tool: "ExitPlanMode"),
            .other(tool: "Mystery"),
        ] {
            let d = decide(subject, auto: true)
            #expect(d.verdict == .card, "\(subject)")
            #expect(d.grant == nil, "\(subject)")
        }
    }

    @Test func planModeDefers() {
        let d = decide(.shell(command: "python3 x.py"), plan: true)
        #expect(d.verdict == .deferToAgent)
        #expect(d.grant == nil)
        #expect(decide(.shell(command: "git push"), plan: true).verdict == .card)
        #expect(decide(.question(tool: "ExitPlanMode"), plan: true).verdict == .card)
    }

    /// Spec 5.4: "always allow" and auto mode are asked first, so `.session`
    /// marks only what passed thanks to the grant.
    @Test func autoModeAndAlwaysAllowKeepTheirLabel() {
        #expect(decide(.shell(command: "git status"), auto: true).grant == .auto)
        #expect(decide(.fileEdit(path: "/Users/u/repo/x.swift"), auto: true).grant == .auto)
        let always = decide(.shell(command: "mytool --run"), allow: AlwaysAllow(global: ["mytool"]))
        #expect(always.grant == .always)
        #expect(always.grantScope == "everywhere")
        #expect(decide(.shell(command: "git status"), auto: true, plan: true).verdict == .deferToAgent)
    }
}
