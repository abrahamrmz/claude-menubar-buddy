import Foundation
import Testing
import BuddyCore

/// A write through a symbolic link lands on what the link points at, so that
/// is the path the policy has to judge. These run against the real disk:
/// where a link leads is the filesystem's answer, not something to stub.
@Suite struct PathPolicyLinkTests {
    private struct Sandbox {
        let base: URL
        /// Canonical, the way the policy will spell them.
        let home: String
        let project: String
        let policy: PathPolicy

        init() throws {
            let fm = FileManager.default
            base = fm.temporaryDirectory.appendingPathComponent("pp-links-\(UUID().uuidString)")
            try fm.createDirectory(at: base.appendingPathComponent("home/.ssh"), withIntermediateDirectories: true)
            try fm.createDirectory(at: base.appendingPathComponent("proj"), withIntermediateDirectories: true)
            let probe = LiveFileProbe()
            home = try #require(probe.resolvedDirectory(base.appendingPathComponent("home").path))
            project = try #require(probe.resolvedDirectory(base.appendingPathComponent("proj").path))
            policy = PathPolicy(home: home, pathDirs: [], tempDirs: [], probe: probe)
        }

        func link(_ name: String, to destination: String) throws {
            try FileManager.default.createSymbolicLink(atPath: project + "/" + name, withDestinationPath: destination)
        }

        func file(_ path: String) {
            FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        }

        func remove() { try? FileManager.default.removeItem(at: base) }
    }

    @Test func aLinkToAProtectedFileIsProtected() throws {
        let box = try Sandbox()
        defer { box.remove() }
        box.file(box.home + "/.zshrc")
        try box.link("z", to: box.home + "/.zshrc")
        #expect(box.policy.protectedSpelling(box.project + "/z") == box.home + "/.zshrc")
        #expect(box.policy.isProtected(box.project + "/z"))
    }

    @Test func aRelativeLinkIsResolvedFromItsOwnFolder() throws {
        let box = try Sandbox()
        defer { box.remove() }
        box.file(box.home + "/.zshrc")
        try box.link("r", to: "../home/.zshrc")
        #expect(box.policy.protectedSpelling(box.project + "/r") == box.home + "/.zshrc")
        #expect(box.policy.isProtected(box.project + "/r"))
    }

    /// Writing through a link whose target is missing creates the target.
    @Test func aLinkToAFileThatDoesNotExistYetIsFollowed() throws {
        let box = try Sandbox()
        defer { box.remove() }
        let target = box.home + "/.config/claude-menubar-buddy/session_auto/claude-abc.json"
        try box.link("g", to: target)
        #expect(box.policy.protectedSpelling(box.project + "/g") == target)
        #expect(box.policy.isProtected(box.project + "/g"))
    }

    @Test func aLinkToAProtectedFolderIsProtected() throws {
        let box = try Sandbox()
        defer { box.remove() }
        try box.link("d", to: box.home + "/.ssh")
        #expect(box.policy.protectedSpelling(box.project + "/d") == box.home + "/.ssh")
        #expect(box.policy.isProtected(box.project + "/d"))
    }

    @Test func aChainOfLinksIsFollowedToTheEnd() throws {
        let box = try Sandbox()
        defer { box.remove() }
        box.file(box.home + "/.zshrc")
        try box.link("b", to: box.home + "/.zshrc")
        try box.link("a", to: "b")
        #expect(box.policy.protectedSpelling(box.project + "/a") == box.home + "/.zshrc")
        #expect(box.policy.isProtected(box.project + "/a"))
    }

    @Test func aLinkToASecretIsSensitive() throws {
        let box = try Sandbox()
        defer { box.remove() }
        box.file(box.project + "/.env")
        try box.link("e", to: ".env")
        #expect(box.policy.sensitiveSpelling(box.project + "/e") == box.project + "/.env")
        #expect(box.policy.isSensitive(box.project + "/e"))
    }

    @Test func aLinkToAnOrdinaryFileIsJudgedByItsTarget() throws {
        let box = try Sandbox()
        defer { box.remove() }
        box.file(box.project + "/notes.txt")
        try box.link("n", to: "notes.txt")
        #expect(box.policy.canonicalize(box.project + "/n") == box.project + "/n")   // the name is kept as spelled
        #expect(!box.policy.isProtected(box.project + "/n"))
        #expect(!box.policy.isSensitive(box.project + "/n"))
    }

    /// Nothing can be written through a loop, so the only thing owed is an answer.
    @Test func aLoopOfLinksStillGetsAnAnswer() throws {
        let box = try Sandbox()
        defer { box.remove() }
        try box.link("a", to: "b")
        try box.link("b", to: "a")
        let answer = box.policy.canonicalize(box.project + "/a")
        #expect([box.project + "/a", box.project + "/b"].contains(answer))
        #expect(!box.policy.isProtected(box.project + "/a"))
    }

    /// The same question, asked the way the hook asks it.
    @Test func theRuleSeesThroughLinks() {
        let probe = StubProbe(dirs: ["/", "/Users/u", "/Users/u/repo"],
                              links: ["/Users/u/repo/z": "/Users/u/.zshrc", "/Users/u/repo/e": ".env"])
        let context = RuleContext(cwd: "/Users/u/repo",
                                  paths: PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: [], probe: probe))
        #expect(CommandRule.assess(.fileEdit(path: "/Users/u/repo/z"), context: context).category == .rutaProtegida)
        #expect(ShellRule.assess("echo x >> z", context: context).category == .rutaProtegida)
        #expect(ShellRule.assess("cp evil z", context: context).category == .rutaProtegida)
        #expect(CommandRule.assess(.fileRead(path: "/Users/u/repo/e"), context: context).category == .sensible)
        #expect(ShellRule.assess("cat e", context: context).category == .sensible)
    }

    /// The usual dotfiles setup: ~/.zshrc is itself a link into a repo. The
    /// name is still the shell profile, whatever the file behind it is called.
    @Test func aProtectedNameThatIsALinkStaysProtected() throws {
        let box = try Sandbox()
        defer { box.remove() }
        try FileManager.default.createDirectory(atPath: box.home + "/dotfiles", withIntermediateDirectories: true)
        box.file(box.home + "/dotfiles/zshrc")
        try FileManager.default.createSymbolicLink(atPath: box.home + "/.zshrc", withDestinationPath: "dotfiles/zshrc")
        #expect(box.policy.isProtected(box.home + "/.zshrc"))
    }

    /// project/a -> ~/.zshrc -> ~/dotfiles/zshrc: neither end has a protected
    /// name, the hop in the middle does.
    @Test func aProtectedNameInTheMiddleOfAChainCounts() throws {
        let box = try Sandbox()
        defer { box.remove() }
        try FileManager.default.createDirectory(atPath: box.home + "/dotfiles", withIntermediateDirectories: true)
        box.file(box.home + "/dotfiles/zshrc")
        try FileManager.default.createSymbolicLink(atPath: box.home + "/.zshrc", withDestinationPath: "dotfiles/zshrc")
        try box.link("a", to: box.home + "/.zshrc")
        #expect(box.policy.isProtected(box.project + "/a"))
    }

    @Test func aSecretNameThatIsALinkStaysSensitive() throws {
        let box = try Sandbox()
        defer { box.remove() }
        box.file(box.project + "/produccion.txt")
        try box.link(".env", to: "produccion.txt")
        #expect(box.policy.isSensitive(box.project + "/.env"))
    }

    /// A sample file is documentation — unless it is a link to the real thing.
    @Test func aSampleNameDoesNotExcuseALinkToTheSecret() throws {
        let box = try Sandbox()
        defer { box.remove() }
        box.file(box.project + "/.env")
        try box.link(".env.example", to: ".env")
        #expect(box.policy.isSensitive(box.project + "/.env.example"))
    }

    /// `echo x > /tmp/l` with `l -> ~/Documents/a.txt` destroys the document,
    /// not something in scratch space.
    @Test func overwritingThroughALinkIsJudgedWhereItLands() {
        let probe = StubProbe(dirs: ["/", "/tmp", "/Users/u/Documents"], files: ["/Users/u/Documents/a.txt"],
                              links: ["/tmp/l": "/Users/u/Documents/a.txt"])
        let policy = PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: ["/tmp"], probe: probe)
        #expect(policy.overwriteIsUnrecoverable("/tmp/l"))
    }

    /// The card has to say where the write really lands, or the path it shows
    /// looks harmless.
    @Test func theReasonNamesBothTheLinkAndItsTarget() {
        let probe = StubProbe(dirs: ["/", "/Users/u", "/Users/u/repo"],
                              links: ["/Users/u/repo/z": "/Users/u/.zshrc", "/Users/u/repo/e": ".env"])
        let context = RuleContext(cwd: "/Users/u/repo",
                                  paths: PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: [], probe: probe))
        #expect(CommandRule.assess(.fileEdit(path: "/Users/u/repo/z"), context: context)
                == Assessment(.rutaProtegida, "escribe en una ruta protegida: /Users/u/repo/z → /Users/u/.zshrc"))
        #expect(ShellRule.assess("echo x >> z", context: context)
                == Assessment(.rutaProtegida, "escribe en una ruta protegida: /Users/u/repo/z → /Users/u/.zshrc"))
        #expect(ShellRule.assess("cat e", context: context)
                == Assessment(.sensible, "toca un archivo sensible: /Users/u/repo/e → /Users/u/repo/.env"))
        // Nothing to add when the path is what it says it is.
        #expect(CommandRule.assess(.fileEdit(path: "/Users/u/.zshrc"), context: context)
                == Assessment(.rutaProtegida, "escribe en una ruta protegida: /Users/u/.zshrc"))
    }
}
