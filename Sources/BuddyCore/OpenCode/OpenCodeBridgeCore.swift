import Foundation

/// One question a form card can present, in the card's terms.
public struct OpenCodeChoice: Equatable {
    public let fieldKey: String
    public let question: String            // field.description ?? field.title ?? field.key
    public let header: String?             // field.title
    public let options: [OpenCodeFormOption]

    public init(fieldKey: String, question: String, header: String?, options: [OpenCodeFormOption]) {
        self.fieldKey = fieldKey
        self.question = question
        self.header = header
        self.options = options
    }
}

/// What the card needs to know about one opencode request, plus the body of
/// the `request_<id>.json` the app already reads for Claude.
public struct OpenCodeCardRequest: Equatable {
    public enum Kind: Equatable { case permission, form }

    public let id: String                  // the opencode permission or form id — also the buddy request id
    public let sessionID: String
    public let kind: Kind
    public let tool: String                // the action ("shell", "edit", …) or "question"
    public let hint: String
    public let hidden: Int
    public let project: String             // last path component of cwd
    public let cwd: String
    public let category: String
    public let critical: Bool
    public let reason: String
    public let choices: [OpenCodeChoice]?  // forms only

    public init(id: String, sessionID: String, kind: Kind, tool: String, hint: String, hidden: Int,
                project: String, cwd: String, category: String, critical: Bool, reason: String,
                choices: [OpenCodeChoice]?) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.tool = tool
        self.hint = hint
        self.hidden = hidden
        self.project = project
        self.cwd = cwd
        self.category = category
        self.critical = critical
        self.reason = reason
        self.choices = choices
    }

    /// The request_<id>.json body: the keys hook.sh writes (id, tool, hint, project, cwd, choices, hidden, ts,
    /// category, critical, reason) plus "agent": "opencode". `choices` uses the hook's shape:
    /// [{"question":…, "header":…, "options":[{"label":…, "description":…}]}], or null.
    public func requestFileJSON(now: Date) -> Data {
        var object: [String: Any] = [
            "id": id,
            "tool": tool,
            "hint": hint,
            "project": project,
            "cwd": cwd,
            "choices": NSNull(),
            "hidden": hidden,
            "agent": "opencode",
            "category": category,
            "critical": critical,
            "reason": reason,
            "ts": now.timeIntervalSince1970,
        ]
        if let choices {
            object["choices"] = choices.map { choice -> [String: Any] in
                var dict: [String: Any] = ["question": choice.question]
                if let header = choice.header { dict["header"] = header }
                dict["options"] = choice.options.map { option -> [String: Any] in
                    var optionDict: [String: Any] = ["label": option.label]
                    if let description = option.description { optionDict["description"] = description }
                    return optionDict
                }
                return dict
            }
        }
        return (try? JSONSerialization.data(withJSONObject: object,
                                            options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }
}

/// What the app should do about one opencode event.
public enum OpenCodeAction: Equatable {
    case autoReply(sessionID: String, requestID: String, log: AutoLogEntry)   // reply "once" now
    case showCard(OpenCodeCardRequest)                                       // after the pending check
    case withdrawCard(id: String)                                            // answered elsewhere
    case turnFinished(sessionID: String, elapsed: Int)
}

/// The bridge's brain: turns opencode events into the actions the app runs,
/// with the same rule and the same auto mode Claude Code goes through. Pure,
/// so the whole decision path is testable without a socket.
public struct OpenCodeBridgeCore {
    public struct Settings {
        public var autoMode: Bool
        public var allowList: AlwaysAllow
        public var paths: PathPolicy
        public init(autoMode: Bool, allowList: AlwaysAllow, paths: PathPolicy) {
            self.autoMode = autoMode
            self.allowList = allowList
            self.paths = paths
        }
    }

    /// The key of a cached `toolCalled` input: call ids are only unique within a
    /// session, so two sessions reusing the same id must not overwrite each other.
    private struct ToolInputKey: Hashable {
        let sessionID: String
        let callID: String
    }

    /// `toolCalled` arrives just before the permission it explains; keeping the
    /// string inputs lets the rule see the whole command rather than the split
    /// resources opencode sends with the ask.
    private var toolInputs: [ToolInputKey: [String: String]] = [:]
    private var toolInputOrder: [ToolInputKey] = []
    private static let toolInputCap = 200

    private var sessionDirectories: [String: String] = [:]
    private var executionStarts: [String: Date] = [:]
    private var pending: [String: OpenCodeCardRequest] = [:]
    private var handled: Set<String> = []

    public init() {}

    public mutating func handle(_ event: OpenCodeEvent, settings: Settings, now: Date) -> [OpenCodeAction] {
        switch event {
        case .permissionAsked(let request, let directory):
            return handlePermission(request, directory: directory, settings: settings, now: now)
        case .toolCalled(let sessionID, let callID, let input):
            remember(input, for: ToolInputKey(sessionID: sessionID, callID: callID))
            return []
        case .formCreated(let form, let directory):
            return handleForm(form, directory: directory)
        case .permissionReplied(_, let requestID):
            return withdraw(requestID)
        case .formClosed(_, let formID):
            return withdraw(formID)
        case .sessionCreated(let sessionID, let directory):
            if let directory { sessionDirectories[sessionID] = directory }
            return []
        case .executionStarted(let sessionID):
            executionStarts[sessionID] = now
            return []
        case .executionFinished(let sessionID):
            guard let start = executionStarts.removeValue(forKey: sessionID) else { return [] }
            return [.turnFinished(sessionID: sessionID, elapsed: Int(now.timeIntervalSince(start)))]
        case .other:
            return []
        }
    }

    public func pending(id: String) -> OpenCodeCardRequest? { pending[id] }

    /// After answering, or when the pending check says it's gone.
    public mutating func forget(id: String) {
        pending.removeValue(forKey: id)
        handled.insert(id)
    }

    // MARK: - Permissions

    private mutating func handlePermission(_ request: OpenCodePermissionRequest, directory: String?,
                                           settings: Settings, now: Date) -> [OpenCodeAction] {
        if let directory { sessionDirectories[request.sessionID] = directory }
        guard !handled.contains(request.id) else { return [] }

        let dir = directory ?? sessionDirectories[request.sessionID] ?? ""
        let toolInput = request.callID.flatMap { toolInputs[ToolInputKey(sessionID: request.sessionID, callID: $0)] }
        let context = RuleContext(cwd: dir, paths: settings.paths)
        let (subject, assessment) = OpenCodeRule.assess(request, toolInput: toolInput, directory: dir, context: context)
        let decision = AutoModePolicy.decide(subject: subject, assessment: assessment, autoMode: settings.autoMode,
                                             allowList: settings.allowList, cwd: dir, planMode: false)
        handled.insert(request.id)

        let project = (dir as NSString).lastPathComponent
        let fullHint = Self.hintText(for: request, toolInput: toolInput)
        if decision.verdict == .pass {
            let log = AutoLogEntry(ts: now.timeIntervalSince1970, agent: "opencode", project: project, cwd: dir,
                                   tool: request.action, hint: String(fullHint.prefix(200)),
                                   category: assessment.category.rawValue)
            return [.autoReply(sessionID: request.sessionID, requestID: request.id, log: log)]
        }

        let (hint, hidden) = Self.clip(fullHint)
        let card = OpenCodeCardRequest(id: request.id, sessionID: request.sessionID, kind: .permission,
                                       tool: request.action, hint: hint, hidden: hidden, project: project,
                                       cwd: dir, category: assessment.category.rawValue,
                                       critical: assessment.critical, reason: assessment.reason, choices: nil)
        pending[request.id] = card
        return [.showCard(card)]
    }

    // MARK: - Forms

    private mutating func handleForm(_ form: OpenCodeForm, directory: String?) -> [OpenCodeAction] {
        if let directory { sessionDirectories[form.sessionID] = directory }
        guard !handled.contains(form.id) else { return [] }
        // Only the question tool, and only when every field is a single choice
        // the card can express. Anything else — multi-select, free text, a
        // login — keeps its own prompt in opencode's terminal.
        guard form.kind == "question", !form.fields.isEmpty,
              form.fields.allSatisfy({ $0.type == "string" && !$0.options.isEmpty }) else { return [] }

        let dir = directory ?? sessionDirectories[form.sessionID] ?? ""
        let choices = form.fields.map {
            OpenCodeChoice(fieldKey: $0.key,
                           question: $0.description ?? $0.title ?? $0.key,
                           header: $0.title,
                           options: $0.options)
        }
        let card = OpenCodeCardRequest(id: form.id, sessionID: form.sessionID, kind: .form, tool: "question",
                                       hint: choices.map(\.question).joined(separator: "\n\n"), hidden: 0,
                                       project: (dir as NSString).lastPathComponent, cwd: dir, category: "pregunta",
                                       critical: false, reason: "pregunta del agente", choices: choices)
        handled.insert(form.id)
        pending[form.id] = card
        return [.showCard(card)]
    }

    // MARK: - Helpers

    private mutating func withdraw(_ id: String) -> [OpenCodeAction] {
        guard pending.removeValue(forKey: id) != nil else { return [] }
        return [.withdrawCard(id: id)]
    }

    private mutating func remember(_ input: [String: String], for key: ToolInputKey) {
        if toolInputs[key] == nil { toolInputOrder.append(key) }
        toolInputs[key] = input
        while toolInputOrder.count > Self.toolInputCap {
            toolInputs.removeValue(forKey: toolInputOrder.removeFirst())
        }
    }

    /// The full text the card shows, before the payload cap.
    private static func hintText(for request: OpenCodePermissionRequest, toolInput: [String: String]?) -> String {
        switch request.action.lowercased() {
        case "shell":
            return toolInput?["command"] ?? request.resources.joined(separator: "; ")
        case "edit":
            if !request.editedFiles.isEmpty {
                return UnifiedDiff.buddyHint(files: request.editedFiles, patches: request.patches)
            }
            if let path = toolInput?["path"], !path.isEmpty { return path }
            return request.resources.joined(separator: "\n")
        default:
            return ([request.action] + request.resources).joined(separator: "\n")
        }
    }

    /// The 20 000-character payload cap hook.sh also applies; `hidden` is what
    /// didn't fit, so the card can say so rather than approve unseen text.
    private static func clip(_ text: String, limit: Int = 20_000) -> (hint: String, hidden: Int) {
        guard text.count > limit else { return (text, 0) }
        return (String(text.prefix(limit)), text.count - limit)
    }
}
