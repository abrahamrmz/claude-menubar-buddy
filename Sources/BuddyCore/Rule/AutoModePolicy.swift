import Foundation

public enum Verdict: String, Equatable {
    case pass
    case card
    case deferToAgent = "defer"
}

public enum Grant: String, Equatable {
    case auto
    case always
}

public struct RuleDecision: Equatable {
    public let verdict: Verdict
    public let assessment: Assessment
    public let grant: Grant?
    /// `everywhere` or `in this project` — only for `.always`.
    public let grantScope: String?
    /// The allowlisted base — only for `.always`.
    public let base: String?

    public init(verdict: Verdict, assessment: Assessment, grant: Grant? = nil,
                grantScope: String? = nil, base: String? = nil) {
        self.verdict = verdict
        self.assessment = assessment
        self.grant = grant
        self.grantScope = grantScope
        self.base = base
    }
}

public enum AutoModePolicy {
    /// The order is the promise: a question never passes on its own, a grant
    /// never covers something critical, and auto mode never reaches past the
    /// categories it was allowed to wave through.
    public static func decide(subject: RuleSubject, assessment: Assessment, autoMode: Bool,
                              allowList: AlwaysAllow, cwd: String?, planMode: Bool) -> RuleDecision {
        if assessment.category == .pregunta {
            return RuleDecision(verdict: .card, assessment: assessment)
        }

        if !assessment.critical, case .shell(let command) = subject,
           let base = AlwaysAllow.commandBase(from: command),
           allowList.allows(base, in: cwd) {
            let scope = allowList.global.contains(base) ? "everywhere" : "in this project"
            return RuleDecision(verdict: .pass, assessment: assessment,
                                grant: .always, grantScope: scope, base: base)
        }

        if autoMode && assessment.category.passesInAutoMode {
            if planMode {
                return RuleDecision(verdict: .deferToAgent, assessment: assessment)
            }
            return RuleDecision(verdict: .pass, assessment: assessment, grant: .auto)
        }

        return RuleDecision(verdict: .card, assessment: assessment)
    }
}
