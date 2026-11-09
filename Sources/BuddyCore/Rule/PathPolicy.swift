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
    /// The text stored in `path` when `path` itself is a symbolic link — not
    /// followed, so a link to something missing still answers — otherwise nil.
    func symlinkDestination(_ path: String) -> String?
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

    public func symlinkDestination(_ path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
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
    // Built once here, not on every question: the rule asks for each word of
    // each command, and one line can hold thousands of commands.
    private let protectedPatterns: [String]
    private let sensitivePatterns: [String]
    /// Secret folders pinned to one place (`~/.aws`): that folder wherever it is named.
    private let pinnedSecretFolders: [String]
    /// Secret folders known only by name (`*/credenciales`): also just a word,
    /// so they count only where a folder called so really exists.
    private let secretFoldersByName: [String]
    /// The protected places pinned to one location — the patterns that start
    /// at the root or at the home folder, not the ones matched by name in any
    /// folder — cut at their first wildcard, folded and lowercased: "/etc",
    /// "/users/u/.gitconfig", "/users/u/.config/claude-menubar-buddy".
    private let pinnedProtected: [String]

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

        let inside = Self.expand(Self.protectedList, home: canonicalHome) + dirs.map { "\($0)/*" }
        self.protectedPatterns = inside + Self.foldersThemselves(inside)
        self.pinnedProtected = inside.filter { $0.hasPrefix("/") }.compactMap { pattern in
            var fixed = String(pattern.prefix { !"*?[".contains($0) })
            while fixed.count > 1 && fixed.hasSuffix("/") { fixed.removeLast() }
            return fixed.isEmpty ? nil : Self.foldedLikeTheVolume(fixed).lowercased()
        }
        let secrets = Self.expand(Self.sensitiveList, home: canonicalHome)
        self.sensitivePatterns = secrets
        let secretFolders = Self.foldersThemselves(secrets)
        self.pinnedSecretFolders = secretFolders.filter { !$0.hasPrefix("*") }
        self.secretFoldersByName = secretFolders.filter { $0.hasPrefix("*") }
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
    ///
    /// A symbolic link in the last existing position is NOT followed here: the
    /// name a command used is part of what gets judged (`spellings`).
    public func canonicalize(_ absolutePath: String) -> String {
        guard let (parent, rest) = settle(absolutePath) else { return "/" }
        return parent + "/" + rest.joined(separator: "/")
    }

    /// The deepest existing directory of `absolutePath`, resolved, and the
    /// components that hang below it — never empty. `parent` is "" for the
    /// root, so `parent + "/" + name` always spells a path. Nil only for "/".
    private func settle(_ absolutePath: String) -> (parent: String, rest: [String])? {
        var path = absolutePath
        if !path.hasPrefix("/") { path = "/" + path }
        while path.hasPrefix("//") { path.removeFirst() }
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        while path.contains("/./") { path = path.replacingOccurrences(of: "/./", with: "/") }
        while path.hasSuffix("/.") { path.removeLast(2) }
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }

        var components = path.split(separator: "/").map(String.init)
        guard let name = components.popLast() else { return nil }

        var parent = ""
        var rest = components + [name]
        for depth in stride(from: components.count, through: 0, by: -1) {
            let candidate = "/" + components[0..<depth].joined(separator: "/")
            guard let resolved = probe.resolvedDirectory(candidate) else { continue }
            let folded = Self.outOfTheDataVolume(resolved)
            parent = folded == "/" ? "" : folded
            rest = Array(components[depth...]) + [name]
            break
        }

        // What hangs below the last existing directory isn't on disk, so it
        // can't be a link, and a `..` after it is plain text: `new/../x` is
        // `x`. One that climbs past `parent` leaves a real path by its real
        // parent, which is its spelling minus the last component.
        var below: [String] = []
        for component in rest {
            if component != ".." {
                below.append(component)
            } else if !below.isEmpty {
                below.removeLast()
            } else {
                parent = (parent as NSString).deletingLastPathComponent
                if parent == "/" { parent = "" }
            }
        }
        if below.isEmpty {
            // Everything cancelled out: the path is `parent` itself.
            if parent.isEmpty { return nil }
            below = [(parent as NSString).lastPathComponent]
            parent = (parent as NSString).deletingLastPathComponent
            if parent == "/" { parent = "" }
        }

        // The data volume is folded last, once `..` is settled: stepping out
        // of the mount and back in (`Data/../Data`) is still the mount.
        let spelled = parent + "/" + below.joined(separator: "/")
        let folded = Self.outOfTheDataVolume(spelled)
        if folded != spelled { return settle(folded) }
        return (parent, below)
    }

    /// APFS mounts the data volume at /System/Volumes/Data and firmlinks its
    /// folders into the root: /System/Volumes/Data/Users/u IS /Users/u, and
    /// realpath(3) leaves the long spelling alone. Fold it, or every pattern
    /// anchored at the home folder or the root can be walked around.
    private static func outOfTheDataVolume(_ path: String) -> String {
        let mount = "/system/volumes/data"
        let lowered = path.lowercased()
        if lowered == mount { return "/" }
        if lowered.hasPrefix(mount + "/") { return String(path.dropFirst(mount.count)) }
        return path
    }

    /// Where the kernel gives up with ELOOP. Nothing can be written through
    /// a loop, so there is no point in walking one any further.
    private static let maxLinkHops = 32

    /// Every spelling a command reaches by naming `absolutePath`: the path as
    /// named and, when a symbolic link sits where the directories end, what
    /// it points at — hop by hop.
    ///
    /// Writing to `notes` when `notes -> ~/.zshrc` rewrites the shell profile,
    /// and when the target is missing the write creates it. The name counts
    /// as well as the target: with dotfiles kept in a repo, `~/.zshrc` is
    /// itself a link to a file called something else, and it is still the
    /// profile.
    ///
    /// This reads the disk as it is now. A link made by the same command
    /// that then uses it isn't there yet — which is why the shell rule judges
    /// `ln` by what it points at, when the link is made.
    private func spellings(_ absolutePath: String) -> [String] {
        var found: [String] = []
        var pending = absolutePath
        for _ in 0...Self.maxLinkHops {
            guard let (parent, rest) = settle(pending) else {
                found.append("/")
                break
            }
            let spelled = parent + "/" + rest.joined(separator: "/")
            if found.contains(spelled) { break }
            found.append(spelled)
            guard let destination = probe.symlinkDestination(parent + "/" + rest[0]) else { break }
            // Relative link text is read from the folder the link lives in.
            let target = destination.hasPrefix("/") ? destination : parent + "/" + destination
            pending = target + rest.dropFirst().map { "/" + $0 }.joined()
        }
        return found
    }

    public func isProtected(_ absolutePath: String) -> Bool {
        protectedSpelling(absolutePath) != nil
    }

    /// The spelling that makes `absolutePath` protected — the path itself, or
    /// what a link leads to — or nil when nothing it reaches is protected.
    public func protectedSpelling(_ absolutePath: String) -> String? {
        spellings(absolutePath).first { Self.matches(Self.foldedLikeTheVolume($0), protectedPatterns) }
    }

    public func isSensitive(_ absolutePath: String) -> Bool {
        sensitiveSpelling(absolutePath) != nil
    }

    /// The spelling of `absolutePath` — as named, or what a link leads to —
    /// that is a protected place pinned to one location or a folder above
    /// one: the root, the home folder, `~/.config`, `~/Library`… Places
    /// protected by name in any folder (`*/.git`, `*/.ssh/*`) don't count, so
    /// a project folder with its `.git` inside is not one. Nil otherwise.
    public func pinnedProtectedContainer(_ absolutePath: String) -> String? {
        spellings(absolutePath).first { spelled in
            let folded = Self.foldedLikeTheVolume(spelled).lowercased()
            if folded == "/" { return true }
            return pinnedProtected.contains { $0 == folded || $0.hasPrefix(folded + "/") }
        }
    }

    /// The spelling that makes `absolutePath` a secret, or nil.
    public func sensitiveSpelling(_ absolutePath: String) -> String? {
        spellings(absolutePath).first { spelled in
            let folded = Self.foldedLikeTheVolume(spelled)
            // A sample file is documentation, not a secret.
            if folded.lowercased().hasSuffix(".env.example") { return false }
            if Self.matches(folded, sensitivePatterns) || Self.matches(folded, pinnedSecretFolders) { return true }
            return Self.matches(folded, secretFoldersByName) && probe.isDirectory(spelled)
        }
    }

    /// How a judged path is named on the card: as the command spelled it,
    /// plus where it really leads when a link took it somewhere else.
    public static func label(_ path: String, landingOn spelling: String) -> String {
        path == spelling ? path : "\(path) → \(spelling)"
    }

    /// True when writing over this path would destroy the only copy: it
    /// exists, it isn't a directory, git can't restore it, and it isn't
    /// scratch space. Judged where the write lands, so a link in /tmp to a
    /// document is the document.
    public func overwriteIsUnrecoverable(_ absolutePath: String) -> Bool {
        guard let path = spellings(absolutePath).last else { return false }
        guard probe.exists(path), !probe.isDirectory(path),
              !probe.isInsideGitWorkTree(path) else { return false }
        for temp in tempDirs where path == temp || path.hasPrefix(temp + "/") { return false }
        return true
    }

    // MARK: - Patterns

    private static let protectedList = [
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
        // /.vol/<device>/<inode> opens a file by number: no name to judge.
        "/.vol/*",
    ]

    private static let sensitiveList = [
        "*/.env", "*/.env.*", "*.pem", "*.key", "*.p12", "*/id_rsa*", "*/id_ed25519*", "*/id_ecdsa*",
        "*/id_dsa*", "*/.netrc",
        "*/.pgpass", "*/.npmrc", "*/.pypirc",
        "*/credenciales/*", "*/secrets.json", "*service_account*.json", "*/google_sa*.json",
        "*cookies*.json",
        "~/.local/state/opencode/service*.json", "~/.claude.json", "*/.claude/settings*.json",
        "~/.aws/*", "~/.kube/*", "~/.config/gh/*", "~/.docker/config.json", "~/.cline/data/*",
        "~/Library/Keychains/*",
        "/.vol/*",
    ]

    private static func expand(_ patterns: [String], home: String) -> [String] {
        patterns.map { $0.replacingOccurrences(of: "~", with: home) }
    }

    /// `folder/*` guards what is inside a folder. A command can name the
    /// folder instead — `cp tool /opt/homebrew/bin`, `mv evil .githooks`,
    /// `cp -r ~/.aws /tmp/a` — and that already reaches everything inside,
    /// so each of those patterns also guards the folder it names.
    ///
    /// Not `*.git/*`: without what follows it would be any file whose name
    /// ends in `.git`.
    private static func foldersThemselves(_ patterns: [String]) -> [String] {
        patterns.compactMap { pattern in
            guard pattern.hasSuffix("/*") else { return nil }
            let folder = String(pattern.dropLast(2))
            guard let name = folder.split(separator: "/").last, !name.contains("*") else { return nil }
            return folder
        }
    }

    /// fnmatch without FNM_PATHNAME, so `*` crosses `/` exactly like `case`
    /// in bash — the behaviour the patterns above were written against.
    /// `folded` comes from `foldedLikeTheVolume`.
    private static func matches(_ folded: String, _ patterns: [String]) -> Bool {
        patterns.contains { fnmatch($0, folded, FNM_CASEFOLD) == 0 }
    }

    private static let ignoredByTheVolume: Set<Unicode.Scalar> = [
        "\u{200C}", "\u{200D}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}",
        "\u{202E}", "\u{206A}", "\u{206B}", "\u{206C}", "\u{206D}", "\u{206E}", "\u{206F}", "\u{FEFF}",
    ]

    /// FNM_CASEFOLD only knows ASCII, and the volume folds more: on APFS the
    /// long s (U+017F) opens the same file as `s`, the Kelvin sign as `k`.
    /// HFS+ also ignores zero-width characters outright, the trick git had to
    /// learn about `.g<U+200C>it`. Fold both here, the way the volume would.
    private static func foldedLikeTheVolume(_ path: String) -> String {
        // Plain ASCII has nothing to fold that FNM_CASEFOLD doesn't already.
        if path.utf8.allSatisfy({ $0 < 0x80 }) { return path }
        var kept = String.UnicodeScalarView()
        for scalar in path.unicodeScalars where !ignoredByTheVolume.contains(scalar) { kept.append(scalar) }
        return String(kept).folding(options: .caseInsensitive, locale: nil)
    }
}
