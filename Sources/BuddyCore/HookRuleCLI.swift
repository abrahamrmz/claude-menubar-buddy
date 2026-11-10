import Foundation

/// The rule behind `buddy-rule`: read one hook payload, answer one verdict.
/// Nothing here touches the screen, so hook.sh can call it on every event.
public enum HookRuleCLI {
    public static func run(input: Data, environment: [String: String],
                           probe: FileProbe = LiveFileProbe(), now: Date = Date()) -> Data {
        let config = configDirectory(environment)

        guard let object = try? JSONSerialization.jsonObject(with: input),
              let dict = object as? [String: Any] else {
            return output(verdict: "card", category: "desconocido", critical: true,
                          reason: "entrada inválida", grant: nil,
                          sessionCoverable: false, askOnTimeout: true)
        }

        let tool = dict["tool_name"] as? String ?? ""
        let toolInput = dict["tool_input"] as? [String: Any] ?? [:]
        let cwd = dict["cwd"] as? String ?? ""
        let planMode = dict["permission_mode"] as? String == "plan"
        // Anything that is not a string counts as no session at all.
        let sessionID = dict["session_id"] as? String ?? ""

        let autoMode = FileManager.default.fileExists(atPath: config.appendingPathComponent("auto_mode").path)
        let allowList = AlwaysAllow.read(from: config.appendingPathComponent("always_allow.json"))
        let paths = PathPolicy.fromEnvironment(environment, probe: probe)
        let context = RuleContext(cwd: cwd, paths: paths)
        let subject = RuleSubject.fromClaudeHook(toolName: tool, toolInput: toolInput)
        let assessment = CommandRule.assess(subject, context: context)

        // Consult and renew the session's grant before deciding. The renewal
        // happens on any verdict, a card or a defer included: it is the
        // session's activity, not a pass. `touch` limits itself to once a
        // minute. This file has no path that calls `grant(` — the only one
        // that creates a grant is the card's button (block 4).
        let grants = SessionGrantStore(configDirectory: config)
        let grantLive = grants.live(agent: "claude", sessionID: sessionID, now: now) != nil
        if grantLive { grants.touch(agent: "claude", sessionID: sessionID, now: now) }

        let decision = AutoModePolicy.decide(subject: subject, assessment: assessment,
                                             autoMode: autoMode, allowList: allowList,
                                             cwd: cwd, planMode: planMode, sessionGrant: grantLive)

        let reason: String
        switch decision.grant {
        case .auto:
            reason = "Modo auto (\(assessment.category.rawValue)) vía Claude Menu Bar Buddy"
        case .always:
            reason = "Always-allowed \(decision.grantScope ?? "everywhere") via Claude Menu Bar Buddy: \(decision.base ?? "")"
        case .session:
            reason = AutoModePolicy.sessionGrantReason(category: assessment.category)
        case .none:
            // Under a live grant a card is there for what it holds back: the
            // card says "sale de tu máquina: git push", not the louder
            // neighbour's "no se puede deshacer: rm".
            reason = grantLive && decision.verdict == .card
                ? assessment.effectiveHold ?? assessment.reason
                : assessment.reason
        }

        if decision.grant == .auto || decision.grant == .session {
            AutoLog.append(AutoLogEntry(ts: now.timeIntervalSince1970,
                                        agent: "claude",
                                        project: (cwd as NSString).lastPathComponent,
                                        cwd: cwd,
                                        tool: tool,
                                        hint: String(hint(for: subject).prefix(200)),
                                        category: assessment.category.rawValue,
                                        grant: decision.grant?.rawValue,
                                        session: SessionGrantStore.isValidSessionID(sessionID) ? sessionID : nil),
                           in: config)
        }

        return output(verdict: decision.verdict.rawValue,
                      category: assessment.category.rawValue,
                      critical: assessment.critical,
                      reason: reason,
                      grant: decision.grant?.rawValue,
                      sessionCoverable: AutoModePolicy.sessionGrantCovers(subject: subject, assessment: assessment),
                      askOnTimeout: asksOnTimeout(assessment, grantLive: grantLive))
    }

    /// Whether the card asks when nobody answers: critical always does, and a
    /// live grant does when it is holding something back. This is what
    /// `hook.sh` does on timeout, from one place.
    public static func asksOnTimeout(_ assessment: Assessment, grantLive: Bool) -> Bool {
        assessment.critical || (grantLive && assessment.effectiveHold != nil)
    }

    /// Claude's SessionEnd hook: revoke this session's grant and note it. The
    /// input is never inspected for `hook_event_name` — revoking is the safe
    /// side. Only `claude` is revoked: an opencode grant with the same id is
    /// left alone. Answers `{}` whatever happens, invalid input included.
    public static func sessionEnd(input: Data, environment: [String: String], now: Date = Date()) -> Data {
        let config = configDirectory(environment)
        if let object = try? JSONSerialization.jsonObject(with: input),
           let dict = object as? [String: Any],
           let sessionID = dict["session_id"] as? String {
            let grants = SessionGrantStore(configDirectory: config)
            if let revoked = grants.revoke(agent: "claude", sessionID: sessionID) {
                AutoLog.append(.grantEnded(revoked, cause: .sessionEnded, ts: now.timeIntervalSince1970),
                               in: config)
            }
        }
        return Data("{}".utf8)
    }

    private static func configDirectory(_ environment: [String: String]) -> URL {
        let home = environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/claude-menubar-buddy")
    }

    private static func hint(for subject: RuleSubject) -> String {
        switch subject {
        case .shell(let command):
            return command
        case .fileEdit(let path), .fileRead(let path):
            return path
        case .web(let tool), .question(let tool), .other(let tool):
            return tool
        }
    }

    private static func output(verdict: String, category: String, critical: Bool,
                               reason: String, grant: String?,
                               sessionCoverable: Bool, askOnTimeout: Bool) -> Data {
        let grantValue: Any = grant.map { $0 as Any } ?? NSNull()
        let object: [String: Any] = [
            "verdict": verdict,
            "category": category,
            "critical": critical,
            "reason": reason,
            "grant": grantValue,
            "session_coverable": sessionCoverable,
            "ask_on_timeout": askOnTimeout,
        ]
        return (try? JSONSerialization.data(withJSONObject: object,
                                            options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
}
