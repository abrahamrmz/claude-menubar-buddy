import Darwin
import Foundation

/// The filesystem questions the path policy needs answered. A protocol so the
/// rule can be tested without the disk, and so a missing directory never
/// turns into a crash.
public protocol FileProbe {
    /// `realpath(3)` when `path` is an existing directory, otherwise nil.
    func resolvedDirectory(_ path: String) -> String?
    func exists(_ path: String) -> Bool
    func isDirectory(_ path: String) -> Bool
    /// Whether some ancestor directory of `path` contains a `.git` entry.
    func isInsideGitWorkTree(_ path: String) -> Bool
}

public struct LiveFileProbe: FileProbe {
    public init() {}

    public func resolvedDirectory(_ path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        // realpath(3), not URL.resolvingSymlinksInPath(): the latter strips
        // /private from /private/tmp, which is precisely the spelling the
        // protected-path comparison depends on.
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public func isInsideGitWorkTree(_ path: String) -> Bool {
        var current = path
        while true {
            if FileManager.default.fileExists(atPath: current + "/.git") { return true }
            if current == "/" || current.isEmpty { return false }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { return false }
            current = parent
        }
    }
}

/// Which paths the buddy refuses to let slip by, and which ones are secret.
///
/// Deliberately a port of what hook.sh already decides: two implementations
/// that drift would mean the card promising one thing and the fast path doing
/// another. Canonical spelling first, then match, because one file answers to
/// many spellings and a case-insensitive volume answers to more.
public struct PathPolicy {
    /// Canonical.
    public let home: String
    public let probe: FileProbe
    private let pathDirs: [String]
    private let tempDirs: [String]

    public init(home: String, pathDirs: [String], tempDirs: [String], probe: FileProbe) {
        self.probe = probe
        let canonicalHome = probe.resolvedDirectory(home) ?? home
        self.home = canonicalHome
        var dirs: [String] = []
        for dir in pathDirs {
            guard dir.hasPrefix("/") else { continue }
            let resolved = probe.resolvedDirectory(dir) ?? dir
            guard resolved != "/", resolved != canonicalHome, !dirs.contains(resolved) else { continue }
            dirs.append(resolved)
        }
        self.pathDirs = dirs
        self.tempDirs = tempDirs.map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
    }

    public static func fromEnvironment(_ env: [String: String], probe: FileProbe) -> PathPolicy {
        let home = env["HOME"] ?? NSHomeDirectory()
        let pathDirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var tempDirs = ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]
        if let tmp = env["TMPDIR"], !tmp.isEmpty {
            tempDirs.append(tmp.hasSuffix("/") ? String(tmp.dropLast()) : tmp)
        }
        return PathPolicy(home: home, pathDirs: pathDirs, tempDirs: tempDirs, probe: probe)
    }

    /// Settles the spelling of an absolute path without requiring it to exist.
    ///
    /// Squeezes repeated slashes and `/./`, then resolves the largest existing
    /// directory prefix and carries the part that isn't there yet. A Write
    /// creates what is missing, so the tail must survive untouched.
    public func canonicalize(_ absolutePath: String) -> String {
        var path = absolutePath
        if !path.hasPrefix("/") { path = "/" + path }
        while path.hasPrefix("//") { path.removeFirst() }
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        while path.contains("/./") { path = path.replacingOccurrences(of: "/./", with: "/") }
        while path.hasSuffix("/.") { path.removeLast(2) }
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }

        var components = path.split(separator: "/").map(String.init)
        guard let name = components.popLast() else { return "/" }

        for depth in stride(from: components.count, through: 0, by: -1) {
            let candidate = "/" + components[0..<depth].joined(separator: "/")
            guard let resolved = probe.resolvedDirectory(candidate) else { continue }
            let tail = (Array(components[depth...]) + [name]).joined(separator: "/")
            return resolved == "/" ? "/" + tail : resolved + "/" + tail
        }
        return path
    }

    public func isProtected(_ absolutePath: String) -> Bool {
        matches(canonicalize(absolutePath), protectedPatterns)
    }

    public func isSensitive(_ absolutePath: String) -> Bool {
        let path = canonicalize(absolutePath)
        // A sample file is documentation, not a secret.
        if path.lowercased().hasSuffix(".env.example") { return false }
        return matches(path, sensitivePatterns)
    }

    /// True when writing over this path would destroy the only copy: it
    /// exists, it isn't a directory, git can't restore it, and it isn't
    /// scratch space.
    public func overwriteIsUnrecoverable(_ absolutePath: String) -> Bool {
        let path = canonicalize(absolutePath)
        guard probe.exists(path), !probe.isDirectory(path),
              !probe.isInsideGitWorkTree(path) else { return false }
        for temp in tempDirs where path == temp || path.hasPrefix(temp + "/") { return false }
        return true
    }

    // MARK: - Patterns

    private var protectedPatterns: [String] {
        expandPatterns([
            "*/.ssh/*", "*/.gnupg/*", "*/Library/LaunchAgents/*", "*/Library/LaunchDaemons/*",
            "*/.git", "*/.git/*", "*.git/*", "*/.claude/*", "~/.claude.json", "*/.mcp.json",
            "~/.config/claude-menubar-buddy/*", "~/Library/Application Support/Claude/*",
            "*/.zshrc", "*/.zshenv", "*/.zprofile", "*/.zlogin", "*/.bashrc", "*/.bash_profile",
            "*/.bash_login", "*/.profile",
            "*/.zlogout", "*/.bash_logout", "*/.oh-my-zsh/*", "*/.config/fish/*", "*/.envrc",
            "~/.gitconfig", "*/.vscode/*", "*/.config/git/*",
            "~/Library/Application Support/Code/User/*", "~/Library/Application Support/Cursor/User/*",
            "/etc/*", "/private/etc/*", "/usr/*", "/bin/*", "/sbin/*", "/Library/*",
            "~/.config/opencode/*", "*/opencode.json", "*/opencode.jsonc", "*/.opencode/*",
            "*/.husky/*", "*/.githooks/*", "*/.pre-commit-config.yaml", "*/lefthook.yml",
            "*/claude-menubar-buddy*/.build/*",
        ]) + expandPatterns([
            // The folders themselves, not only what lives inside them: a
            // `cp -t ~/Library/LaunchAgents` or `mv x .husky` names the
            // directory, and that already writes there.
            "*/.ssh", "*/.gnupg", "*/Library/LaunchAgents", "*/Library/LaunchDaemons", "*/.claude",
            "~/.config/claude-menubar-buddy", "*/.oh-my-zsh", "*/.config/fish", "*/.vscode",
            "*/.config/git", "~/.config/opencode", "*/.opencode", "*/.husky", "*/.githooks",
        ]) + pathDirs.map { "\($0)/*" }
    }

    private var sensitivePatterns: [String] {
        expandPatterns([
            "*/.env", "*/.env.*", "*.pem", "*.key", "*.p12", "*/id_rsa*", "*/id_ed25519*", "*/.netrc",
            "*/.pgpass", "*/.npmrc", "*/.pypirc",
            "*/credenciales/*", "*/secrets.json", "*service_account*.json", "*/google_sa*.json",
            "*cookies*.json",
            "~/.local/state/opencode/service*.json", "~/.claude.json", "*/.claude/settings*.json",
            "~/.aws/*", "~/.kube/*", "~/.config/gh/*", "~/.docker/config.json", "~/.cline/data/*",
            "~/Library/Keychains/*",
        ])
    }

    private func expandPatterns(_ patterns: [String]) -> [String] {
        patterns.map { $0.replacingOccurrences(of: "~", with: home) }
    }

    /// fnmatch without FNM_PATHNAME, so `*` crosses `/` exactly like `case`
    /// in bash — the behaviour the patterns above were written against.
    private func matches(_ path: String, _ patterns: [String]) -> Bool {
        patterns.contains { fnmatch($0, path, FNM_CASEFOLD) == 0 }
    }
}
