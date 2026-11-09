import Darwin
import Foundation

/// One session's "auto completo": while its file in the store is live, every
/// request that session makes runs unless a hold says otherwise. The grant
/// belongs to a session id, not to a folder.
public struct SessionGrant: Codable, Equatable {
    public let agent: String        // "claude" | "opencode"
    public let sessionID: String
    public let cwd: String
    public let project: String
    public let grantedAt: Double    // timeIntervalSince1970
    public let trigger: String      // "<herramienta>: <inicio del hint>", ya recortado por quien concede

    public init(agent: String, sessionID: String, cwd: String, project: String,
                grantedAt: Double, trigger: String) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.project = project
        self.grantedAt = grantedAt
        self.trigger = trigger
    }
}

/// A grant as the menu lists it: the grant and when it was last active.
public struct SessionGrantStatus: Equatable {
    public let grant: SessionGrant
    public let lastActivity: Date

    public init(grant: SessionGrant, lastActivity: Date) {
        self.grant = grant
        self.lastActivity = lastActivity
    }
}

/// The on-disk store of session grants. This is the security boundary of
/// "auto completo": a live file here means "this session runs everything but
/// publishing". Names are validated and rejected, never repaired, so nothing
/// a session id says can climb out of the folder. Asking never deletes —
/// sweeping is the app's job — and renewing never creates, so a revoked or
/// never-granted session cannot come back through a touch.
public struct SessionGrantStore {
    public static let directoryName = "session_auto"
    /// Eight hours without activity and the grant is no longer live.
    public static let idleLimit: TimeInterval = 8 * 60 * 60
    /// A touch renews at most once a minute.
    public static let touchInterval: TimeInterval = 60
    /// A modification date up to a minute in the future still counts.
    public static let futureSkew: TimeInterval = 60

    private let directory: URL

    public init(configDirectory: URL) {
        directory = configDirectory.appendingPathComponent(Self.directoryName)
    }

    // MARK: - Names

    public static func isValidAgent(_ agent: String) -> Bool {
        agent == "claude" || agent == "opencode"
    }

    /// Between 1 and 128 ASCII scalars: letters, digits, `-` and `_`. Looked
    /// at as scalars, not Characters, so no non-ASCII letter or digit slips
    /// through (`isLetter` would accept `ａ`, `isNumber` would accept `٣`).
    public static func isValidSessionID(_ id: String) -> Bool {
        let scalars = id.unicodeScalars
        guard (1...128).contains(scalars.count) else { return false }
        return scalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F: return true
            default: return false
            }
        }
    }

    public static func fileName(agent: String, sessionID: String) -> String? {
        guard isValidAgent(agent), isValidSessionID(sessionID) else { return nil }
        return "\(agent)-\(sessionID).json"
    }

    // MARK: - Reading

    /// The grant in `name` and its modification date, or nil. It only counts
    /// when the item is a regular file (a symlink or a folder does not), has
    /// a modification date, decodes, and its own agent and session id match
    /// the file name — so foreign files and half-written temporaries are
    /// skipped, never trusted.
    private func read(_ name: String) -> (grant: SessionGrant, modified: Date)? {
        let path = directory.appendingPathComponent(name).path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let modified = attributes[.modificationDate] as? Date,
              let data = FileManager.default.contents(atPath: path),
              let grant = try? JSONDecoder().decode(SessionGrant.self, from: data),
              Self.fileName(agent: grant.agent, sessionID: grant.sessionID) == name else {
            return nil
        }
        return (grant, modified)
    }

    /// Exactly 60 s in the future still counts; 61 does not. Exactly 8 h idle
    /// already does not.
    private func isLive(_ modified: Date, now: Date) -> Bool {
        modified.timeIntervalSince(now) <= Self.futureSkew
            && now.timeIntervalSince(modified) < Self.idleLimit
    }

    /// Every readable grant in the folder, oldest first and, on a tie, by
    /// name. Foreign files, temporaries and mismatched names are left alone.
    private func entries() -> [(name: String, grant: SessionGrant, modified: Date)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            guard let entry = read(name) else { return nil }
            return (name, entry.grant, entry.modified)
        }.sorted { a, b in
            a.grant.grantedAt != b.grant.grantedAt
                ? a.grant.grantedAt < b.grant.grantedAt
                : a.name < b.name
        }
    }

    // MARK: - Granting and asking

    /// Writes the grant, atomically and 0600, and returns whether it did. An
    /// invalid agent or session id writes nothing at all, not even the folder.
    @discardableResult
    public func grant(_ grant: SessionGrant, now: Date = Date()) -> Bool {
        guard let name = Self.fileName(agent: grant.agent, sessionID: grant.sessionID) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            // Also when the folder was already there with a looser mode.
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(grant)

            // A temporary beside the final name, born 0600, so a reader sees
            // either "no grant" or the whole grant, never a half-written file.
            let temporary = directory.appendingPathComponent(".tmp-" + UUID().uuidString).path
            let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { return false }
            var writeFailed = false
            data.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if written <= 0 { writeFailed = true; break }
                    offset += written
                }
            }
            close(fd)
            guard !writeFailed else { unlink(temporary); return false }
            do {
                try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: temporary)
            } catch {
                unlink(temporary)
                return false
            }
            // rename replaces whatever holds the final name, a symlink
            // included, without writing through it.
            guard rename(temporary, directory.appendingPathComponent(name).path) == 0 else {
                unlink(temporary)
                return false
            }
            return true
        } catch {
            return false
        }
    }

    /// The live grant for this agent and session, or nil. Never deletes, not
    /// even an expired one: deleting is the app's sweep.
    public func live(agent: String, sessionID: String, now: Date = Date()) -> SessionGrant? {
        guard let name = Self.fileName(agent: agent, sessionID: sessionID),
              let entry = read(name), isLive(entry.modified, now: now) else { return nil }
        return entry.grant
    }

    /// Renews the grant's activity, but only a live one, at most once a
    /// minute. Never creates the file or the folder, never revives an expired
    /// grant, and never reaches through a link (read already rejected those).
    public func touch(agent: String, sessionID: String, now: Date = Date()) {
        guard let name = Self.fileName(agent: agent, sessionID: sessionID),
              let entry = read(name),
              isLive(entry.modified, now: now),
              now.timeIntervalSince(entry.modified) > Self.touchInterval else { return }
        try? FileManager.default.setAttributes([.modificationDate: now],
                                               ofItemAtPath: directory.appendingPathComponent(name).path)
    }

    // MARK: - Revoking

    /// Deletes that one grant and returns what it was, or nil. An invalid
    /// name does nothing. `removeItem` on a link removes the link, not its
    /// target.
    @discardableResult
    public func revoke(agent: String, sessionID: String) -> SessionGrant? {
        guard let name = Self.fileName(agent: agent, sessionID: sessionID) else { return nil }
        let grant = read(name)?.grant
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        return grant
    }

    /// Deletes every grant in the folder, live or expired, and returns those
    /// it could delete, in listing order. Nothing else in the folder is
    /// touched.
    public func revokeAll() -> [SessionGrant] {
        var removed: [SessionGrant] = []
        for entry in entries() {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.name))
            removed.append(entry.grant)
        }
        return removed
    }

    // MARK: - Listing and sweeping

    /// The live grants, oldest first. Never deletes.
    public func list(now: Date = Date()) -> [SessionGrantStatus] {
        entries()
            .filter { isLive($0.modified, now: now) }
            .map { SessionGrantStatus(grant: $0.grant, lastActivity: $0.modified) }
    }

    /// Deletes and returns the grants that are not live: the expired and the
    /// ones dated more than a minute in the future (invisible in the menu and
    /// self-reviving as the clock catches up).
    public func sweepExpired(now: Date = Date()) -> [SessionGrant] {
        var swept: [SessionGrant] = []
        for entry in entries() where !isLive(entry.modified, now: now) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.name))
            swept.append(entry.grant)
        }
        return swept
    }
}
