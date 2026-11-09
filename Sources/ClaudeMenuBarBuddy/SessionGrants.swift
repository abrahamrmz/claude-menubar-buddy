import AppKit
import BuddyCore

// The app's side of the session grants: the in-memory cache of the live ones,
// the idle-expiry sweep, and the sweep that approves the waiting Claude
// requests a grant covers. Which ones is decided in BuddyCore
// (SessionGrantCard.sweep); the files are SessionGrantStore's. opencode's
// cards are swept by the bridge (OpenCodeBridge.sweepCoveredCards).
extension AppDelegate {
    /// One idle-expiry sweep every this many poll() ticks (about 30 s).
    static let sessionGrantSweepEveryTicks = 30

    /// A fresh URL on every call: URL caches resource values, and a cached
    /// modification date would never change.
    var sessionGrantsFolderURL: URL {
        dirURL.appendingPathComponent(SessionGrantStore.directoryName, isDirectory: true)
    }

    private func sessionGrantsFolderModified() -> Date? {
        (try? sessionGrantsFolderURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    /// Re-lists the live grants. True when the list changed.
    @discardableResult
    func reloadSessionGrantCache() -> Bool {
        sessionGrantsFolderStamp = sessionGrantsFolderModified()
        let fresh = sessionGrantStore.list()
        guard fresh != sessionGrants else { return false }
        sessionGrants = fresh
        return true
    }

    /// Once per poll() tick: the cache follows the folder, and every 30 ticks
    /// the grants idle for 8 hours are deleted and logged.
    func tickSessionGrants() {
        sessionGrantTicks += 1
        var changed = false
        if sessionGrantTicks >= Self.sessionGrantSweepEveryTicks {
            sessionGrantTicks = 0
            let now = Date()
            for gone in sessionGrantStore.sweepExpired(now: now) {
                AutoLog.append(.grantEnded(gone, cause: .idle, ts: now.timeIntervalSince1970), in: dirURL)
            }
            changed = reloadSessionGrantCache()
        } else if sessionGrantsFolderModified() != sessionGrantsFolderStamp {
            changed = reloadSessionGrantCache()
        }
        if changed { refreshSessionGrantViews() }
    }

    /// Repaints whatever shows the grants.
    func refreshSessionGrantViews() {
        if let req = currentRequest {
            applyPendingStatusIcon(for: req, queued: lastQueuedCount)
        } else {
            updateIdleTitle()
        }
    }

    /// Approves the waiting Claude requests a live grant covers. Returns their ids.
    @discardableResult
    func sweepQueueBySessionGrants(_ requests: [PendingRequest]) -> Set<String> {
        guard !sessionGrants.isEmpty else { return [] }
        let items = requests.map { req in
            GrantSweepItem(id: req.id, agent: req.agent, session: req.session,
                           coverable: req.sessionCoverable, hasChoices: req.choices != nil)
        }
        var swept = Set<String>()
        for match in SessionGrantCard.sweep(items, grants: sessionGrants.map(\.grant)) {
            // The cache can trail an idle expiry by up to 30 s; the file decides.
            guard sessionGrantStore.live(agent: match.grant.agent, sessionID: match.grant.sessionID) != nil,
                  let req = requests.first(where: { $0.id == match.id }) else { continue }
            approveBySessionGrant(req)
            swept.insert(req.id)
        }
        return swept
    }

    /// One swept Claude request: a response_ file of "allow" for its hook,
    /// and a line in auto_decisions.jsonl with grant "session" — never in
    /// decisions.jsonl, which is what you answered, and nobody clicked this.
    private func approveBySessionGrant(_ req: PendingRequest) {
        guard req.agent == "claude", let session = req.session else { return }
        DebugLog.note("swept \(req.id) (\(req.tool)) by the session grant")
        let payload: [String: Any] = [
            "decision": "allow",
            "reason": SessionGrantCard.sweptReason(category: req.category ?? "desconocido"),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: dirURL.appendingPathComponent("response_\(req.id).json"), options: [.atomic])
        }
        AutoLog.append(SessionGrantCard.sweptEntry(agent: "claude", session: session, project: req.project,
                                                   cwd: req.cwd, tool: req.tool, hint: req.hint,
                                                   category: req.category, now: Date()),
                       in: dirURL)
        try? FileManager.default.removeItem(at: dirURL.appendingPathComponent("request_\(req.id).json"))
        respondedIds.insert(req.id)
    }
}
