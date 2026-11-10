import Foundation
import Testing
import BuddyCore

// The grant store is the security boundary of "auto completo": a file in it
// means "this session runs everything but publishing". Every test passes
// `now:` and sets modification dates by hand, so nothing depends on the clock.
@Suite struct SessionGrantStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Config {
        let url: URL
        var store: SessionGrantStore { SessionGrantStore(configDirectory: url) }
        var grantsDir: URL { url.appendingPathComponent("session_auto") }

        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("grants-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        func cleanup() { try? FileManager.default.removeItem(at: url) }
        func file(_ name: String) -> URL { grantsDir.appendingPathComponent(name) }
        func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: file(name).path) }

        /// Writes `text` by hand at session_auto/<name>, with `modified` as its modification date.
        func plant(_ name: String, _ text: String, modified: Date) throws {
            let target = file(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try text.write(to: target, atomically: false, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: target.path)
        }

        func setModified(_ name: String, _ date: Date) throws {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file(name).path)
        }

        func modified(_ name: String) throws -> Date? {
            try FileManager.default.attributesOfItem(atPath: file(name).path)[.modificationDate] as? Date
        }

        func permissions(_ url: URL) throws -> Int? {
            try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        }
    }

    private func sample(_ agent: String = "claude", _ id: String = "ses-a",
                        grantedAt: Double = 1_800_000_000) -> SessionGrant {
        SessionGrant(agent: agent, sessionID: id, cwd: "/tmp/proyX", project: "proyX",
                     grantedAt: grantedAt, trigger: "Bash: python3 x.py")
    }

    /// The on-disk shape, written by hand rather than by the encoder under test.
    private func json(agent: String, id: String) throws -> String {
        let object: [String: Any] = ["agent": agent, "sessionID": id, "cwd": "/tmp/proyX", "project": "proyX",
                                     "grantedAt": 1_800_000_000, "trigger": "Bash: ls"]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    // MARK: - Names

    @Test func constantsAreTheSpecs() {
        #expect(SessionGrantStore.directoryName == "session_auto")
        #expect(SessionGrantStore.idleLimit == 28_800)
        #expect(SessionGrantStore.touchInterval == 60)
        #expect(SessionGrantStore.futureSkew == 60)
    }

    @Test(arguments: ["a", "ses_1", "ses_01JABCdef", "e575efb6-a7ad-4a1e-ab95-e32b6755393f",
                      String(repeating: "x", count: 128)])
    func acceptsPlainIDs(id: String) {
        #expect(SessionGrantStore.isValidSessionID(id))
    }

    /// Rejected, never repaired: no trimming, no normalizing, no escaping.
    @Test(arguments: ["", "../x", "a/b", "abc\n", " abc", "sesión", "sesio\u{301}n", "a.b", ".", "..",
                      "a b", "a\u{0}b", "\u{FF41}", "\u{0663}", String(repeating: "x", count: 129)])
    func rejectsEverythingElse(id: String) {
        #expect(!SessionGrantStore.isValidSessionID(id), "accepted: \(id.debugDescription)")
        #expect(SessionGrantStore.fileName(agent: "claude", sessionID: id) == nil)
    }

    @Test func onlyTheTwoKnownAgents() {
        #expect(SessionGrantStore.isValidAgent("claude"))
        #expect(SessionGrantStore.isValidAgent("opencode"))
        for bad in ["", "Claude", "OPENCODE", "codex", "claude ", "claude-x", "../claude"] {
            #expect(!SessionGrantStore.isValidAgent(bad), "accepted: \(bad.debugDescription)")
            #expect(SessionGrantStore.fileName(agent: bad, sessionID: "ses-a") == nil)
        }
        #expect(SessionGrantStore.fileName(agent: "claude", sessionID: "ses-a") == "claude-ses-a.json")
        #expect(SessionGrantStore.fileName(agent: "opencode", sessionID: "ses_1") == "opencode-ses_1.json")
    }

    // MARK: - Granting and asking

    @Test func aGrantIsLiveForItsOwnSessionOnly() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample(), now: t0))
        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: t0) == sample())
        #expect(c.store.live(agent: "claude", sessionID: "ses-b", now: t0) == nil)
        #expect(c.store.live(agent: "opencode", sessionID: "ses-a", now: t0) == nil)
        #expect(c.exists("claude-ses-a.json"))
    }

    @Test func aHandWrittenGrantReadsBack() throws {
        let c = try Config(); defer { c.cleanup() }
        try c.plant("opencode-ses_1.json", try json(agent: "opencode", id: "ses_1"), modified: t0)
        #expect(c.store.live(agent: "opencode", sessionID: "ses_1", now: t0) == SessionGrant(
            agent: "opencode", sessionID: "ses_1", cwd: "/tmp/proyX", project: "proyX",
            grantedAt: 1_800_000_000, trigger: "Bash: ls"))
    }

    @Test func grantingAgainReplacesTheGrant() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample(), now: t0))
        let second = SessionGrant(agent: "claude", sessionID: "ses-a", cwd: "/tmp/proyX", project: "proyX",
                                  grantedAt: 1_800_000_500, trigger: "Edit: notas.txt")
        #expect(c.store.grant(second, now: t0.addingTimeInterval(500)))
        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: t0.addingTimeInterval(500)) == second)
    }

    @Test func grantRefusesInvalidNamesAndWritesNothing() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(!c.store.grant(sample("codex", "ses-a"), now: t0))
        #expect(!c.store.grant(sample("claude", "../x"), now: t0))
        #expect(!c.store.grant(sample("claude", ""), now: t0))
        #expect(!c.store.grant(sample("claude", "abc\n"), now: t0))
        let left = (try? FileManager.default.contentsOfDirectory(atPath: c.grantsDir.path)) ?? []
        #expect(left.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: c.url.appendingPathComponent("x.json").path))
    }

    /// For each invalid id, a file sits exactly where a careless implementation
    /// that glued the id into the path would look. None of it may count.
    @Test(arguments: ["../x", "a/b", "", "sesión", String(repeating: "x", count: 129)])
    func invalidIDsFindNothingEvenWhenAFileIsThere(id: String) throws {
        let c = try Config(); defer { c.cleanup() }
        let name = "claude-\(id).json"
        try c.plant(name, try json(agent: "claude", id: id), modified: t0)
        #expect(c.store.live(agent: "claude", sessionID: id, now: t0) == nil)
        c.store.touch(agent: "claude", sessionID: id, now: t0.addingTimeInterval(600))
        #expect(try c.modified(name) == t0)
        #expect(c.store.revoke(agent: "claude", sessionID: id) == nil)
        #expect(c.exists(name))
    }

    @Test func aTrailingNewlineIsNotTrimmedIntoAnotherSession() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample("claude", "abc"), now: t0))
        #expect(c.store.live(agent: "claude", sessionID: "abc\n", now: t0) == nil)
        #expect(c.store.revoke(agent: "claude", sessionID: "abc\n") == nil)
        #expect(c.store.live(agent: "claude", sessionID: "abc", now: t0) != nil)
    }

    @Test func anUnknownAgentFindsNothing() throws {
        let c = try Config(); defer { c.cleanup() }
        try c.plant("codex-ses-a.json", try json(agent: "codex", id: "ses-a"), modified: t0)
        #expect(c.store.live(agent: "codex", sessionID: "ses-a", now: t0) == nil)
        #expect(c.store.list(now: t0).isEmpty)
    }

    // MARK: - When a grant counts as live

    @Test func aGrantDiesAfterEightHoursIdle() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample(), now: t0))
        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: t0.addingTimeInterval(8 * 3600 - 1)) != nil)
        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: t0.addingTimeInterval(8 * 3600 + 1)) == nil)
        // Asking never deletes: only the app's sweep does.
        #expect(c.exists("claude-ses-a.json"))
    }

    @Test func aModificationDateFromTheFutureIsNotLive() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample(), now: t0))
        try c.setModified("claude-ses-a.json", t0.addingTimeInterval(61))
        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: t0) == nil)
        try c.setModified("claude-ses-a.json", t0.addingTimeInterval(60))
        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: t0) != nil)
    }

    @Test func contentMustMatchTheFileName() throws {
        let c = try Config(); defer { c.cleanup() }
        try c.plant("claude-ses-a.json", try json(agent: "claude", id: "ses-b"), modified: t0)
        try c.plant("claude-ses-c.json", try json(agent: "opencode", id: "ses-c"), modified: t0)
        try c.plant("claude-ses-d.json", "no es json", modified: t0)
        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: t0) == nil)
        #expect(c.store.live(agent: "claude", sessionID: "ses-b", now: t0) == nil)
        #expect(c.store.live(agent: "claude", sessionID: "ses-c", now: t0) == nil)
        #expect(c.store.live(agent: "opencode", sessionID: "ses-c", now: t0) == nil)
        #expect(c.store.live(agent: "claude", sessionID: "ses-d", now: t0) == nil)
        #expect(c.store.list(now: t0).isEmpty)
    }

    /// The real clock here, not t0: a link's own modification date is "now"
    /// and Foundation can't change it (setAttributes follows the link), so
    /// only a fresh link proves the type check and not the age check.
    @Test func aSymlinkInPlaceOfTheFileIsNotAGrant() throws {
        let c = try Config(); defer { c.cleanup() }
        let now = Date()
        // A perfectly valid, fresh grant, outside the folder…
        let elsewhere = c.url.appendingPathComponent("real.json")
        let text = try json(agent: "claude", id: "ses-a")
        try text.write(to: elsewhere, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: elsewhere.path)
        // …reached through a link with the right name.
        try FileManager.default.createDirectory(at: c.grantsDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: c.file("claude-ses-a.json"), withDestinationURL: elsewhere)

        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: now) == nil)
        #expect(c.store.list(now: now).isEmpty)
        // touch does not reach through the link.
        c.store.touch(agent: "claude", sessionID: "ses-a", now: now.addingTimeInterval(600))
        let target = try FileManager.default.attributesOfItem(atPath: elsewhere.path)[.modificationDate] as? Date
        #expect(abs((target ?? .distantPast).timeIntervalSince(now)) < 1)
        // Granting replaces the link itself and never writes through it.
        #expect(c.store.grant(sample(), now: now))
        #expect(try String(contentsOf: elsewhere, encoding: .utf8) == text)
        let type = try FileManager.default.attributesOfItem(atPath: c.file("claude-ses-a.json").path)[.type] as? FileAttributeType
        #expect(type == .typeRegular)
    }

    @Test func revokingALinkRemovesTheLinkNotItsTarget() throws {
        let c = try Config(); defer { c.cleanup() }
        let elsewhere = c.url.appendingPathComponent("real.json")
        try json(agent: "claude", id: "ses-a").write(to: elsewhere, atomically: false, encoding: .utf8)
        try FileManager.default.createDirectory(at: c.grantsDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: c.file("claude-ses-a.json"), withDestinationURL: elsewhere)
        #expect(c.store.revoke(agent: "claude", sessionID: "ses-a") == nil)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: c.file("claude-ses-a.json").path)) == nil)
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    // MARK: - Renewing

    @Test func touchRenewsAtMostOncePerMinute() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample(), now: t0))
        c.store.touch(agent: "claude", sessionID: "ses-a", now: t0.addingTimeInterval(60))
        #expect(try c.modified("claude-ses-a.json") == t0)
        c.store.touch(agent: "claude", sessionID: "ses-a", now: t0.addingTimeInterval(61))
        #expect(try c.modified("claude-ses-a.json") == t0.addingTimeInterval(61))
        // Eight hours now count from the touch, not from the grant.
        #expect(c.store.live(agent: "claude", sessionID: "ses-a",
                             now: t0.addingTimeInterval(61 + 8 * 3600 - 1)) != nil)
    }

    @Test func touchNeverCreatesNorRevives() throws {
        let c = try Config(); defer { c.cleanup() }
        // Never granted: no file, not even the folder.
        c.store.touch(agent: "claude", sessionID: "ses-z", now: t0)
        #expect(!FileManager.default.fileExists(atPath: c.grantsDir.path))
        // Revoked: renewing fails and does not bring it back.
        #expect(c.store.grant(sample(), now: t0))
        c.store.revoke(agent: "claude", sessionID: "ses-a")
        c.store.touch(agent: "claude", sessionID: "ses-a", now: t0.addingTimeInterval(120))
        #expect(!c.exists("claude-ses-a.json"))
        #expect(c.store.live(agent: "claude", sessionID: "ses-a", now: t0.addingTimeInterval(120)) == nil)
        // Expired: stays expired.
        #expect(c.store.grant(sample("claude", "ses-b"), now: t0))
        c.store.touch(agent: "claude", sessionID: "ses-b", now: t0.addingTimeInterval(8 * 3600 + 1))
        #expect(try c.modified("claude-ses-b.json") == t0)
        #expect(c.store.live(agent: "claude", sessionID: "ses-b", now: t0.addingTimeInterval(8 * 3600 + 1)) == nil)
    }

    // MARK: - Revoking

    @Test func revokeDeletesOnlyThatGrantAndReturnsIt() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample("claude", "ses-a"), now: t0))
        #expect(c.store.grant(sample("claude", "ses-b"), now: t0))
        #expect(c.store.grant(sample("opencode", "ses-a"), now: t0))
        #expect(c.store.revoke(agent: "claude", sessionID: "ses-a") == sample("claude", "ses-a"))
        #expect(c.store.revoke(agent: "claude", sessionID: "ses-a") == nil)
        #expect(!c.exists("claude-ses-a.json"))
        #expect(c.store.live(agent: "claude", sessionID: "ses-b", now: t0) != nil)
        #expect(c.store.live(agent: "opencode", sessionID: "ses-a", now: t0) != nil)
    }

    @Test func revokeAllEmptiesTheFolderOfGrantsOnly() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample("opencode", "ses_2", grantedAt: 1_800_000_200), now: t0))
        #expect(c.store.grant(sample("claude", "ses-1", grantedAt: 1_800_000_100), now: t0))
        try c.plant("notas.txt", "hola", modified: t0)
        let gone = c.store.revokeAll()
        #expect(gone.map(\.sessionID) == ["ses-1", "ses_2"])
        #expect(c.store.list(now: t0).isEmpty)
        #expect(c.exists("notas.txt"))
    }

    // MARK: - Files on disk

    @Test func folderIs700FileIs600AndNoTemporaryIsLeft() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample(), now: t0))
        #expect(try c.permissions(c.grantsDir) == 0o700)
        #expect(try c.permissions(c.file("claude-ses-a.json")) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.grantsDir.path) == ["claude-ses-a.json"])
    }

    @Test func aLooseExistingFolderIsTightenedTo700() throws {
        let c = try Config(); defer { c.cleanup() }
        try FileManager.default.createDirectory(at: c.grantsDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        #expect(c.store.grant(sample(), now: t0))
        #expect(try c.permissions(c.grantsDir) == 0o700)
    }

    // MARK: - Listing and sweeping

    @Test func listShowsOnlyLiveGrantsOldestFirstAndIgnoresStrangers() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample("opencode", "ses_2", grantedAt: 1_800_000_200), now: t0))
        #expect(c.store.grant(sample("claude", "ses-1", grantedAt: 1_800_000_100), now: t0))
        #expect(c.store.grant(sample("claude", "vieja", grantedAt: 1_799_000_000),
                              now: t0.addingTimeInterval(-8 * 3600 - 1)))
        let valid = try json(agent: "claude", id: "ses-x")
        try c.plant(".tmp-0123", valid, modified: t0)                 // a write in progress
        try c.plant("claude-ses-x.json.tmp", valid, modified: t0)
        try c.plant("notas.txt", "hola", modified: t0)
        try c.plant("codex-ses-x.json", valid, modified: t0)
        let listed = c.store.list(now: t0.addingTimeInterval(10))
        #expect(listed.map(\.grant.sessionID) == ["ses-1", "ses_2"])
        #expect(listed.map(\.lastActivity) == [t0, t0])
        // list never deletes, not even what it skipped.
        #expect(c.exists("claude-vieja.json"))
    }

    @Test func sweepDeletesTheExpiredAndTheFutureOnly() throws {
        let c = try Config(); defer { c.cleanup() }
        #expect(c.store.grant(sample("claude", "viva"), now: t0))
        #expect(c.store.grant(sample("claude", "vieja"), now: t0.addingTimeInterval(-8 * 3600 - 1)))
        #expect(c.store.grant(sample("opencode", "futura"), now: t0.addingTimeInterval(3600)))
        try c.plant("notas.txt", "hola", modified: t0.addingTimeInterval(-9 * 3600))
        let swept = c.store.sweepExpired(now: t0)
        #expect(Set(swept.map(\.sessionID)) == ["vieja", "futura"])
        #expect(c.store.live(agent: "claude", sessionID: "viva", now: t0) != nil)
        #expect(!c.exists("claude-vieja.json"))
        #expect(!c.exists("opencode-futura.json"))
        #expect(c.exists("notas.txt"))
    }
}
