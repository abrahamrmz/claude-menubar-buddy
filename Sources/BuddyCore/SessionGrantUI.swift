import Foundation

/// The card's session-grant button, the menu's session-grant rows and the
/// queue sweep: the wording and the pure decisions live here, so the app only
/// paints and connects. A session grant is "auto completo" for one session.
public enum SessionGrantCard {
    public static let buttonTitle = "Permitir y dejar esta sesión en auto completo"           // contrato
    public static let buttonToolTip = "Todo lo local de esta sesión pasa sin tarjeta, salvo publicar, hasta que la cierres, la apagues en el menú o pasen 8 h sin que pida nada."
    public static let buttonAccessibility = "Permitir, y dejar esta sesión en auto completo: pasa todo salvo publicar"
    public static let revokeAllTitle = "Apagar en todas"                                       // contrato
    public static let grantFailedTitle = "No se pudo prender el auto completo"
    public static let grantFailedBody = "La concesión no se guardó. La tarjeta sigue esperando tu respuesta."

    /// Spec 9.1: coverable && agent is "claude" or "opencode" && a valid session id && not a question.
    public static func offersGrant(agent: String?, session: String?, coverable: Bool, hasChoices: Bool) -> Bool {
        guard coverable, !hasChoices, let agent, let session else { return false }
        // The store's own validation, never a second one: what opens a grant
        // has to be exactly what can be written.
        return SessionGrantStore.isValidAgent(agent) && SessionGrantStore.isValidSessionID(session)
    }

    /// "Auto completo: 1 sesión" / "Auto completo: N sesiones".
    public static func menuTitle(count: Int) -> String {
        "Auto completo: \(count) \(count == 1 ? "sesión" : "sesiones")"
    }

    /// "<proyecto> · <Claude Code|opencode> · desde HH:mm · <disparador>", local time.
    public static func rowTitle(_ grant: SessionGrant, timeZone: TimeZone = .current) -> String {
        let project = grant.project.isEmpty ? "sin proyecto" : grant.project
        return "\(project) · \(agentName(grant.agent)) · desde \(clock(grant.grantedAt, timeZone)) · \(grant.trigger)"
    }

    /// The menu row's tooltip: last activity and when the 8 idle hours run out.
    public static func rowToolTip(_ status: SessionGrantStatus, timeZone: TimeZone = .current) -> String {
        let expiry = status.lastActivity.addingTimeInterval(SessionGrantStore.idleLimit)
        let activity = clock(status.lastActivity.timeIntervalSince1970, timeZone)
        let ends = clock(expiry.timeIntervalSince1970, timeZone)
        return "Última actividad \(activity). Se apaga sola a las \(ends) si la sesión no pide nada. Clic para apagarla ya."
    }

    /// ", 1 sesión en auto completo" / ", N sesiones en auto completo"; "" with 0.
    public static func accessibilitySuffix(count: Int) -> String {
        count == 0 ? "" : ", \(count) \(count == 1 ? "sesión" : "sesiones") en auto completo"
    }

    /// The grant a click on the card writes.
    public static func makeGrant(agent: String, sessionID: String, cwd: String?, project: String?,
                                 tool: String, hint: String, now: Date) -> SessionGrant {
        SessionGrant(agent: agent, sessionID: sessionID, cwd: cwd ?? "",
                     project: projectName(project, cwd: cwd), grantedAt: now.timeIntervalSince1970,
                     trigger: trigger(tool: tool, hint: hint))
    }

    /// "<tool>: <first line of the hint>", the line trimmed and cut to 60 characters.
    public static func trigger(tool: String, hint: String) -> String {
        let firstLine = hint.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        var line = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.count > 60 { line = String(line.prefix(59)) + "…" }
        return line.isEmpty ? tool : "\(tool): \(line)"
    }

    /// The same wording buddy-rule gives a request that passes by the grant.
    public static func sweptReason(category: String) -> String {
        if let known = RuleCategory(rawValue: category) {
            return AutoModePolicy.sessionGrantReason(category: known)
        }
        return "Auto completo de esta sesión (\(category)) vía Claude Menu Bar Buddy"
    }

    /// The auto_decisions.jsonl line of a request the queue sweep approved.
    public static func sweptEntry(agent: String, session: String, project: String?, cwd: String?,
                                  tool: String, hint: String, category: String?, now: Date) -> AutoLogEntry {
        AutoLogEntry(ts: now.timeIntervalSince1970, agent: agent,
                     project: projectName(project, cwd: cwd), cwd: cwd ?? "",
                     tool: tool, hint: String(hint.prefix(200)),
                     category: category ?? "desconocido", grant: "session", session: session)
    }

    /// Spec 9.1 step 3: the waiting Claude requests a live grant covers, in input order.
    /// opencode's cards are never here: the bridge sweeps them over the session tree.
    public static func sweep(_ items: [GrantSweepItem], grants: [SessionGrant]) -> [GrantSweepMatch] {
        items.compactMap { item in
            guard item.agent == "claude",
                  offersGrant(agent: item.agent, session: item.session, coverable: item.coverable,
                              hasChoices: item.hasChoices),
                  let session = item.session,
                  let grant = grants.first(where: { $0.agent == "claude" && $0.sessionID == session })
            else { return nil }
            return GrantSweepMatch(id: item.id, grant: grant)
        }
    }

    // MARK: - Helpers

    private static func agentName(_ agent: String) -> String {
        agent == "claude" ? "Claude Code" : agent
    }

    /// The given project, else the folder name of `cwd`, else "". Same rule in
    /// `makeGrant` and `sweptEntry`.
    private static func projectName(_ project: String?, cwd: String?) -> String {
        if let project, !project.isEmpty { return project }
        if let cwd, !cwd.isEmpty { return (cwd as NSString).lastPathComponent }
        return ""
    }

    private static func clock(_ ts: Double, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: ts))
    }
}

/// What the queue sweep needs to know about one waiting request.
public struct GrantSweepItem: Equatable {
    public let id: String
    public let agent: String?
    public let session: String?
    public let coverable: Bool
    public let hasChoices: Bool
    public init(id: String, agent: String?, session: String?, coverable: Bool, hasChoices: Bool) {
        self.id = id
        self.agent = agent
        self.session = session
        self.coverable = coverable
        self.hasChoices = hasChoices
    }
}

/// One waiting request a live grant covers, and the grant that covers it.
public struct GrantSweepMatch: Equatable {
    public let id: String
    public let grant: SessionGrant
    public init(id: String, grant: SessionGrant) {
        self.id = id
        self.grant = grant
    }
}
