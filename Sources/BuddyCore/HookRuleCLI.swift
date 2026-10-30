import Foundation

/// The rule behind `buddy-rule`: read one hook payload, answer one verdict.
/// Nothing here touches the screen, so hook.sh can call it on every event.
public enum HookRuleCLI {
    public static func run(input: Data, environment: [String: String],
                           probe: FileProbe = LiveFileProbe(), now: Date = Date()) -> Data {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let config = URL(fileURLWithPath: home).appendingPathComponent(".config/claude-menubar-buddy")

        guard let object = try? JSONSerialization.jsonObject(with: input),
              let dict = object as? [String: Any] else {
            return output(verdict: "card", category: "desconocido", critical: true,
                          reason: "entrada inválida", grant: nil)
        }

        let tool = dict["tool_name"] as? String ?? ""
        let toolInput = dict["tool_input"] as? [String: Any] ?? [:]
        let cwd = dict["cwd"] as? String ?? ""
        let planMode = dict["permission_mode"] as? String == "plan"

        let autoMode = FileManager.default.fileExists(atPath: config.appendingPathComponent("auto_mode").path)
        let allowList = AlwaysAllow.read(from: config.appendingPathComponent("always_allow.json"))
        let paths = PathPolicy.fromEnvironment(environment, probe: probe)
        let context = RuleContext(cwd: cwd, paths: paths)
        let subject = RuleSubject.fromClaudeHook(toolName: tool, toolInput: toolInput)
        let assessment = CommandRule.assess(subject, context: context)
        let decision = AutoModePolicy.decide(subject: subject, assessment: assessment,
                                             autoMode: autoMode, allowList: allowList,
                                             cwd: cwd, planMode: planMode)

        let reason: String
        switch decision.grant {
        case .auto:
            reason = "Modo auto (\(assessment.category.rawValue)) vía Claude Menu Bar Buddy"
        case .always:
            reason = "Always-allowed \(decision.grantScope ?? "everywhere") via Claude Menu Bar Buddy: \(decision.base ?? "")"
        case .none:
            reason = assessment.reason
        }

        if decision.grant == .auto {
            AutoLog.append(AutoLogEntry(ts: now.timeIntervalSince1970,
                                        agent: "claude",
                                        project: (cwd as NSString).lastPathComponent,
                                        cwd: cwd,
                                        tool: tool,
                                        hint: String(hint(for: subject).prefix(200)),
                                        category: assessment.category.rawValue),
                           in: config)
        }

        return output(verdict: decision.verdict.rawValue,
                      category: assessment.category.rawValue,
                      critical: assessment.critical,
                      reason: reason,
                      grant: decision.grant?.rawValue)
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
                               reason: String, grant: String?) -> Data {
        let grantValue: Any = grant.map { $0 as Any } ?? NSNull()
        let object: [String: Any] = [
            "verdict": verdict,
            "category": category,
            "critical": critical,
            "reason": reason,
            "grant": grantValue,
        ]
        return (try? JSONSerialization.data(withJSONObject: object,
                                            options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
}
