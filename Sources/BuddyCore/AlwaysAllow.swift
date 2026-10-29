import Foundation

/// The buddy's Bash allowlist, in two scopes: commands allowed everywhere,
/// and commands allowed only in the session that granted them.
///
/// Projects are keyed by the session's **absolute cwd**, not by its name.
/// Two checkouts can both be called `api`, and a grant leaking between them
/// is exactly the kind of thing nobody would ever notice. The match is exact
/// for the same reason a prefix would be wrong: `/repo` as a prefix also
/// covers `/repo-secrets`, and a grant that widens by accident is the one
/// failure this file exists to prevent.
public struct AlwaysAllow: Equatable {
    public var global: [String]
    public var projects: [String: [String]]

    public init(global: [String] = [], projects: [String: [String]] = [:]) {
        self.global = global
        self.projects = projects
    }

    /// Mirrors hook.sh's lookup — kept in Swift so the settings table can say
    /// what the hook would actually do, but the hook remains the authority
    /// (it decides with the app not running).
    public func allows(_ base: String, in cwd: String?) -> Bool {
        if global.contains(base) { return true }
        guard let cwd = cwd, !cwd.isEmpty else { return false }
        return projects[cwd]?.contains(base) ?? false
    }

    /// Reads the allowlist file, treating anything unreadable as empty.
    public static func read(from url: URL) -> AlwaysAllow {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return AlwaysAllow() }
        // The file was a bare array before grants had scopes. Everything in
        // one was granted everywhere, so that is where it stays: narrowing a
        // permission the user gave would be a surprise in the safe direction,
        // but a surprise, and a command that silently stopped being allowed
        // would just look like the buddy had broken.
        if let legacy = obj as? [String] { return AlwaysAllow(global: legacy) }
        guard let dict = obj as? [String: Any] else { return AlwaysAllow() }
        return AlwaysAllow(global: dict["global"] as? [String] ?? [],
                           projects: dict["projects"] as? [String: [String]] ?? [:])
    }

    /// First token of the command — must match hook.sh's extraction so the
    /// button's promise ("gh won't ask again") is exactly what the fast path
    /// later honors. Returns nil for anything that doesn't look like a plain
    /// command name.
    ///
    /// Also nil the moment the command can chain, substitute, redirect or
    /// expand. hook.sh refuses to fast-path those — an allowlist entry names
    /// one command and can only speak for one command — so offering the
    /// button there would be promising something that never happens, on the
    /// exact shapes where the promise would be most dangerous if it did.
    /// The character set is the same one hook.sh screens on; they have to
    /// agree or the button and the fast path drift apart.
    ///
    /// An env assignment in front is nil for the same reason, and it is the
    /// subtler case: the word stays `ls`, but `PATH=` changes which binary
    /// that word finds and `DYLD_INSERT_LIBRARIES=` loads foreign code into
    /// the right one. hook.sh sends those to a card, so no button here.
    public static func commandBase(from command: String) -> String? {
        let shellMetacharacters = CharacterSet(charactersIn: ";&|<>()`$\\\n")
        guard command.rangeOfCharacter(from: shellMetacharacters) == nil else { return nil }
        guard let token = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else { return nil }
        guard token.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) == nil else { return nil }
        let base = String(token)
        guard base.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil else { return nil }
        return base
    }
}
