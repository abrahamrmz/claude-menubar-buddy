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

    @Test(arguments: [
        "/Users/u/.ssh", "/Users/u/.gnupg", "/Users/u/Library/LaunchAgents", "/Library/LaunchDaemons",
        "/tmp/p/.claude", "/Users/u/.config/claude-menubar-buddy", "/Users/u/.oh-my-zsh", "/Users/u/.config/fish",
        "/tmp/p/.vscode", "/Users/u/.config/git", "/Users/u/.config/opencode", "/tmp/p/.opencode",
        "/tmp/p/.husky", "/tmp/p/.githooks", "/tmp/p/.HUSKY",
    ])
    func protectedDirectoriesThemselves(path: String) {
        #expect(policy.isProtected(path), "the directory itself must be protected: \(path)")
    }

    @Test(arguments: ["/tmp/p/sshkeys-docs", "/tmp/p/husky-notes.md", "/tmp/p/src/opencode-client.ts", "/tmp/p/claude.md"])
    func lookAlikesAreNotProtected(path: String) {
        #expect(!policy.isProtected(path))
    }

    // A destination can name the folder instead of the file inside it:
    // `cp tool /opt/homebrew/bin` writes /opt/homebrew/bin/tool.
    @Test(arguments: [
        "/opt/homebrew/bin", "/bin", "/etc", "/private/etc", "/usr", "/sbin", "/Library",
        "/Users/u/Library/Application Support/Claude", "/Users/u/Library/Application Support/Code/User",
        "/Users/u/Desktop/repos/claude-menubar-buddy/.build", "/OPT/Homebrew/bin",
    ])
    func foldersThatHoldProtectedFilesAreProtected(path: String) {
        #expect(policy.isProtected(path), "naming the folder already writes inside it: \(path)")
    }

    @Test(arguments: [
        "/", "/tmp", "/Users/u", "/Users/u/Library", "/Users/u/.config", "/opt/homebrew", "/opt",
        "/tmp/proyecto/bin", "/tmp/proyecto/etc", "/Users/u/Library/Application Support",
        // `*.git/*` guards what a bare repo holds; a file or a new folder called so is just a name.
        "/tmp/repo.git", "/tmp/p/notes.git",
    ])
    func foldersAboveProtectedOnesStayOrdinary(path: String) {
        #expect(!policy.isProtected(path), "should not be protected: \(path)")
    }

    // Same for secrets: `cp -r ~/.aws /tmp/a` carries the credentials to a
    // place where no pattern recognises them any more.
    @Test(arguments: [
        "/Users/u/.aws", "/Users/u/.kube", "/Users/u/.config/gh", "/Users/u/.cline/data",
        "/Users/u/Library/Keychains", "/Users/u/.AWS",
    ])
    func foldersThatHoldSecretsAreSensitive(path: String) {
        #expect(policy.isSensitive(path), "copying the folder copies the secrets: \(path)")
    }

    @Test(arguments: ["/", "/tmp/p", "/Users/u", "/Users/u/.config", "/Users/u/.cline", "/Users/u/Library", "/tmp/p/credenciales-docs"])
    func foldersAboveSecretsStayOrdinary(path: String) {
        #expect(!policy.isSensitive(path), "should not be sensitive: \(path)")
    }

    /// `credenciales` is also just a word: an argument to echo, a search
    /// term. It only names secrets where a folder called so really exists.
    @Test func aSecretsFolderKnownByNameCountsOnlyWhereItExists() {
        let probe = StubProbe(dirs: ["/", "/tmp/p", "/tmp/p/credenciales"])
        let withFolder = PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: [], probe: probe)
        #expect(withFolder.isSensitive("/tmp/p/credenciales"))
        #expect(!policy.isSensitive("/tmp/p/credenciales"))
    }

    // The data volume is mounted at /System/Volumes/Data and its folders are
    // firmlinked into the root: both spellings open the same file, and
    // realpath(3) leaves the long one alone.
    @Test(arguments: [
        "/System/Volumes/Data/Users/u/.gitconfig", "/System/Volumes/Data/Users/u/.config/claude-menubar-buddy/auto_mode",
        "/system/volumes/data/Users/u/.gitconfig", "/System/Volumes/Data/private/etc/hosts",
        "/System/Volumes/Data/opt/homebrew/bin/jq", "/System/Volumes/Data/Users/u/.claude.json",
        // The fold has to come after `..` is settled, or stepping out and back in walks around it.
        "/System/Volumes/Data/../Data/Users/u/.gitconfig", "/System/Volumes/Data/./../Data/Users/u/.gitconfig",
        "/System/Volumes/Data/..//Data/Users/u/.gitconfig", "/System/Volumes/Data/x/../Users/u/.gitconfig",
    ])
    func theDataVolumeSpellingIsTheSameFile(path: String) {
        #expect(policy.isProtected(path), "should be protected: \(path)")
    }

    @Test func theDataVolumeSpellingOfASecretIsSensitive() {
        #expect(policy.isSensitive("/System/Volumes/Data/Users/u/.aws/credentials"))
        #expect(policy.isSensitive("/System/Volumes/Data/Users/u/.docker/config.json"))
    }

    /// A folder link can lead into the data volume too.
    @Test func aFolderThatResolvesIntoTheDataVolumeIsFolded() {
        let probe = StubProbe(dirs: ["/"], aliases: ["/tmp/d": "/System/Volumes/Data/Users/u"])
        let p = PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: [], probe: probe)
        #expect(p.canonicalize("/tmp/d/.gitconfig") == "/Users/u/.gitconfig")
        #expect(p.isProtected("/tmp/d/.gitconfig"))
    }

    /// /.vol/<device>/<inode> opens a file by number, with no name to judge.
    @Test func aFileOpenedByNumberIsNeverOrdinary() {
        #expect(policy.isProtected("/.vol/16777220/8675309"))
        #expect(policy.isSensitive("/.vol/16777220/8675309"))
    }

    // The volume folds more than ASCII case: the long s (U+017F) is an `s`
    // and the Kelvin sign (U+212A) is a `k`, and HFS+ ignores zero-width
    // characters altogether. Each of these opens the protected file.
    @Test(arguments: [
        "/Users/u/.z\u{017F}hrc", "/Users/u/.\u{017F}sh/authorized_keys", "/tmp/p/.g\u{200C}it/config",
        "/tmp/p/.hus\u{212A}y/pre-commit", "/Users/u/.git\u{FEFF}config",
    ])
    func lookAlikeLettersTheVolumeFoldsAreFoldedHere(path: String) {
        #expect(policy.isProtected(path), "should be protected: \(path)")
    }

    @Test(arguments: ["/Users/u/.ssh/id_ecdsa", "/Users/u/.ssh/id_dsa", "/tmp/p/llaves/id_ecdsa.bak"])
    func otherPrivateKeyNamesAreSensitive(path: String) {
        #expect(policy.isSensitive(path), "should be sensitive: \(path)")
    }

    @Test func lookAlikeLettersInASecretNameAreFolded() {
        #expect(policy.isSensitive("/tmp/p/.env.\u{017F}taging"))
        #expect(policy.isSensitive("/tmp/p/\u{017F}ecrets.json"))
    }

    // What isn't there yet can't be a link, so `..` after it is plain text.
    @Test func dotDotAfterAMissingFolderIsCollapsed() {
        let probe = StubProbe(dirs: ["/", "/Users/u/repo"])
        let p = PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: [], probe: probe)
        #expect(p.canonicalize("/Users/u/repo/nuevo/../../.gitconfig") == "/Users/u/.gitconfig")
        #expect(p.canonicalize("/Users/u/repo/nuevo/..") == "/Users/u/repo")
        #expect(p.canonicalize("/Users/u/repo/a/b/../c.txt") == "/Users/u/repo/a/c.txt")
        #expect(p.canonicalize("/../..") == "/")
        #expect(p.isProtected("/Users/u/repo/nuevo/../../.gitconfig"))
    }
}
