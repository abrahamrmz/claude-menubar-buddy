import Foundation
import Testing
import BuddyCore

@Suite struct PathPolicyTests {
    private let policy = PathPolicy(home: "/Users/u",
                                    pathDirs: ["/usr/bin", "/bin", "/opt/homebrew/bin", "relative/bin", "/Users/u"],
                                    tempDirs: ["/tmp", "/private/tmp"],
                                    probe: StubProbe())

    @Test(arguments: [
        "/Users/u/.ssh/config", "/Users/u/.gnupg/gpg.conf", "/Users/u/.claude/settings.json",
        "/Users/u/.config/claude-menubar-buddy/always_allow.json", "/Users/u/Library/LaunchAgents/evil.plist",
        "/Users/u/Library/Application Support/Claude/x.json", "/Users/u/.zshrc", "/tmp/p/.git/hooks/pre-commit",
        "/etc/hosts", "/Library/LaunchDaemons/evil.plist", "/tmp/p/.claude/settings.local.json", "/tmp/p/.git/config",
        "/tmp/p/.envrc", "/tmp/p/.vscode/tasks.json", "/Users/u/.gitconfig", "/Users/u/.oh-my-zsh/custom/x.zsh",
        "/Users/u/.config/fish/config.fish", "/private/etc/hosts", "/tmp/p/.GIT/config", "/Users/u/.SSH/authorized_keys",
        "/Users/u/.ZSHRC", "/Users/u//.gitconfig", "/Users/u/./.gitconfig", "//etc/paths.d/evil", "/tmp/p/sub/.git",
        "/tmp/repo.git/hooks/post-receive", "/Users/u/.config/git/config", "/Users/u/.claude.json", "/tmp/p/.mcp.json",
        "/Users/u/.zlogout", "/Users/u/Library/Application Support/Code/User/tasks.json",
        // ampliadas en esta ronda
        "/Users/u/.config/opencode/opencode.json", "/tmp/p/opencode.jsonc", "/tmp/p/opencode.json",
        "/tmp/p/.opencode/plugins/x.ts", "/tmp/p/.husky/pre-commit", "/tmp/p/.githooks/pre-push",
        "/tmp/p/.pre-commit-config.yaml", "/tmp/p/lefthook.yml", "/opt/homebrew/bin/ls", "/usr/bin/jq",
        "/Users/u/Desktop/repos/claude-menubar-buddy/.build/debug/ClaudeMenuBarBuddy",
    ])
    func protectedPaths(path: String) {
        #expect(policy.isProtected(path), "should be protected: \(path)")
    }

    @Test(arguments: [
        "/tmp/proyecto/src/main.swift", "/tmp/proyecto/src/hooks/useThing.ts", "/tmp/proyecto/package.json",
        "/Users/u/Documents/notas.txt", "/tmp/proyecto/gitconfig-template.md", "/tmp/proyecto/src/git/client.ts",
        "/tmp/digit/file.txt", "/tmp/proyecto/docs/vscode-setup.md",
        "/Users/u/Desktop/repos/claude-menubar-buddy-opencode/Sources/x.swift",
        "/Users/u/notes.md",   // home is in PATH above, but home itself is never treated as a PATH dir
    ])
    func ordinaryPaths(path: String) {
        #expect(!policy.isProtected(path), "should not be protected: \(path)")
    }

    @Test(arguments: [
        "/tmp/p/.env", "/tmp/p/.env.production", "/tmp/p/certs/server.pem", "/tmp/p/x.key", "/Users/u/.ssh/id_ed25519",
        "/Users/u/.netrc", "/tmp/p/.npmrc", "/tmp/p/credenciales/sa.json", "/tmp/p/secrets.json",
        "/tmp/p/my_service_account_x.json", "/tmp/p/google_sa_prod.json", "/tmp/p/archivos/fb_cookies.json",
        "/Users/u/.local/state/opencode/service.json", "/Users/u/.claude.json", "/tmp/p/.claude/settings.local.json",
        "/Users/u/.aws/credentials", "/Users/u/.kube/config", "/Users/u/.config/gh/hosts.yml",
        "/Users/u/.docker/config.json", "/Users/u/.cline/data/locks/hub/production.json",
        "/Users/u/Library/Keychains/login.keychain-db", "/tmp/p/.ENV",
    ])
    func sensitivePaths(path: String) {
        #expect(policy.isSensitive(path), "should be sensitive: \(path)")
    }

    @Test(arguments: ["/tmp/p/.env.example", "/tmp/p/environment.md", "/tmp/p/src/key_utils.swift", "/tmp/p/README.md"])
    func notSensitive(path: String) {
        #expect(!policy.isSensitive(path))
    }

    @Test func canonicalizeCollapsesSpellings() {
        #expect(policy.canonicalize("//Users/u//./.gitconfig") == "/Users/u/.gitconfig")
    }

    @Test func canonicalizeResolvesSymlinksAndKeepsTheMissingTail() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("pp-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: base.appendingPathComponent("link"), withDestinationURL: real)
        defer { try? fm.removeItem(at: base) }
        let live = PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: [], probe: LiveFileProbe())
        let realResolved = LiveFileProbe().resolvedDirectory(real.path)!
        #expect(live.canonicalize(base.path + "/link/new/file.txt") == realResolved + "/new/file.txt")
    }

    @Test func overwriteRules() {
        let probe = StubProbe(dirs: ["/", "/Users/u/repo", "/Users/u/Documents"],
                              files: ["/Users/u/Documents/a.txt", "/Users/u/repo/b.txt", "/tmp/x.json", "/private/tmp/x.json"],
                              gitRoots: ["/Users/u/repo"])
        let p = PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: ["/tmp", "/private/tmp"], probe: probe)
        #expect(p.overwriteIsUnrecoverable("/Users/u/Documents/a.txt"))     // exists, no git, not temp
        #expect(!p.overwriteIsUnrecoverable("/Users/u/repo/b.txt"))         // inside git
        #expect(!p.overwriteIsUnrecoverable("/tmp/x.json"))                 // temp
        #expect(!p.overwriteIsUnrecoverable("/Users/u/Documents/nuevo.txt")) // does not exist
        #expect(!p.overwriteIsUnrecoverable("/Users/u/Documents"))          // a directory
    }
}
