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
    /// Whether a session grant would cover this request (AutoModePolicy.sessionGrantCovers). Always false for forms.
    public let sessionCoverable: Bool

    public init(id: String, sessionID: String, kind: Kind, tool: String, hint: String, hidden: Int,
                project: String, cwd: String, category: String, critical: Bool, reason: String,
                choices: [OpenCodeChoice]?, sessionCoverable: Bool = false) {
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
        self.sessionCoverable = sessionCoverable
    }

    /// The request_<id>.json body: the keys hook.sh writes (id, tool, hint, project, cwd, choices, hidden, ts,
    /// category, critical, reason, session, session_coverable) plus "agent": "opencode". `choices` uses the
    /// hook's shape: [{"question":…, "header":…, "options":[{"label":…, "description":…}]}], or null.
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
            "session": sessionID,
            "session_coverable": sessionCoverable,
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
    /// GET /api/session/{id}; feed back .sessionInfo, .sessionGone or .lineageUnavailable.
    case resolveLineage(sessionID: String)
    /// The session holding the grant asked for something: renew its activity.
    case touchSessionGrant(sessionID: String)
    /// The session ended or no longer exists: delete its grant.
    case revokeSessionGrant(sessionID: String)
}

/// The bridge's brain: turns opencode events into the actions the app runs,
/// with the same rule and the same auto mode Claude Code goes through. Pure,
/// so the whole decision path is testable without a socket.
public struct OpenCodeBridgeCore {
    public struct Settings {
        public var autoMode: Bool
        public var allowList: AlwaysAllow
        public var paths: PathPolicy
        /// The opencode sessions with a live grant.
        public var sessionGrants: Set<String>
        public init(autoMode: Bool, allowList: AlwaysAllow, paths: PathPolicy, sessionGrants: Set<String> = []) {
            self.autoMode = autoMode
            self.allowList = allowList
            self.paths = paths
            self.sessionGrants = sessionGrants
        }
    }

    /// How many parents a request may climb to reach its grant.
    public static let lineageDepthLimit = 8
    /// How long a coverable request waits for an unknown parent before it becomes a card.
    public static let lineageWait: TimeInterval = 2

    /// What the bridge knows about a session's parent. An enum, not a `String?`
    /// dictionary value: assigning nil to a dictionary removes the key.
    private enum Lineage: Equatable {
        case root
        case child(of: String)
    }

    private enum LineageWalk: Equatable {
        case granted(String)   // this session, the requester or an ancestor, holds a grant
        case root(String)      // the chain reaches this root and no grant on the way
        case missing(String)   // this session's parent is unknown
        case broken            // a cycle, more than lineageDepthLimit parents, a gone or invalid session
    }

    /// A coverable request waiting for its lineage. Not in `handled` yet, never a card yet.
    private struct HeldRequest {
        let request: OpenCodePermissionRequest
        let directory: String?
        let deadline: Date
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

    private var lineage: [String: Lineage] = [:]
    private var goneSessions: Set<String> = []
    private var lineageAsked: [String: Date] = [:]
    private var held: [(entry: HeldRequest, missing: String)] = []   // arrival order

    public init() {}

    public mutating func handle(_ event: OpenCodeEvent, settings: Settings, now: Date) -> [OpenCodeAction] {
        // No clock of its own: every event, a text delta included, is when the
        // core notices a wait that ran out.
        let expired = releaseHeld(settings: settings, now: now) { $0.entry.deadline <= now }
        return expired + dispatch(event, settings: settings, now: now)
    }

    private mutating func dispatch(_ event: OpenCodeEvent, settings: Settings, now: Date) -> [OpenCodeAction] {
        switch event {
        case .permissionAsked(let request, let directory):
            return handlePermission(request, directory: directory, settings: settings, now: now)
        case .toolCalled(let sessionID, let callID, let input):
            remember(input, for: ToolInputKey(sessionID: sessionID, callID: callID))
            return []
        case .formCreated(let form, let directory):
            return handleForm(form, directory: directory)
        case .permissionReplied(_, let requestID):
            return replyReceived(requestID)
        case .formClosed(_, let formID):
            return withdraw(formID)
        case .sessionCreated(let sessionID, let directory, let parentID):
            if let directory { sessionDirectories[sessionID] = directory }
            lineage[sessionID] = parentID.map { .child(of: $0) } ?? .root
            return []
        case .executionStarted(let sessionID):
            executionStarts[sessionID] = now
            return []
        case .executionFinished(let sessionID):
            guard let start = executionStarts.removeValue(forKey: sessionID) else { return [] }
            return [.turnFinished(sessionID: sessionID, elapsed: Int(now.timeIntervalSince(start)))]
        case .sessionEnded(let sessionID):
            return settings.sessionGrants.contains(sessionID) ? [.revokeSessionGrant(sessionID: sessionID)] : []
        case .sessionInfo(let sessionID, let parentID, let archived):
            lineage[sessionID] = parentID.map { .child(of: $0) } ?? .root
            lineageAsked[sessionID] = nil
            var effective = settings
            var actions: [OpenCodeAction] = []
            if archived && settings.sessionGrants.contains(sessionID) {
                actions.append(.revokeSessionGrant(sessionID: sessionID))
                // A grant this event revokes covers nothing else in the same event.
                effective.sessionGrants.remove(sessionID)
            }
            return actions + revisitHeld(settings: effective, now: now) + askNextLinks(now: now)
        case .sessionGone(let sessionID):
            goneSessions.insert(sessionID)
            lineageAsked[sessionID] = nil
            var actions: [OpenCodeAction] = []
            if settings.sessionGrants.contains(sessionID) {
                actions.append(.revokeSessionGrant(sessionID: sessionID))
            }
            return actions + releaseHeld(settings: settings, now: now) { $0.missing == sessionID }
        case .lineageUnavailable(let sessionID):
            lineageAsked[sessionID] = nil
            return releaseHeld(settings: settings, now: now) { $0.missing == sessionID }
        case .other:
            return []
        }
    }

    public func pending(id: String) -> OpenCodeCardRequest? { pending[id] }

    /// Every card still waiting for an answer, for the bridge to re-check
    /// after a reconnect. Unordered.
    public var pendingCards: [OpenCodeCardRequest] { Array(pending.values) }

    /// After answering, or when the pending check says it's gone.
    public mutating func forget(id: String) {
        pending.removeValue(forKey: id)
        held.removeAll { $0.entry.request.id == id }
        handled.insert(id)
    }

    // MARK: - Lineage

    /// The root of `sessionID` when its whole chain of parents is known, else nil.
    public func rootIfKnown(_ sessionID: String) -> String? {
        if case .root(let root) = walk(from: sessionID, grants: []) { return root }
        return nil
    }

    /// rootIfKnown ?? sessionID: the session a click on its card grants.
    public func grantSessionID(for sessionID: String) -> String {
        rootIfKnown(sessionID) ?? sessionID
    }

    /// The session whose parent the bridge should fetch now that the card for `id`
    /// is on screen, so the root is known if the user clicks (spec 8). nil when
    /// that card is not a pending coverable permission, its chain is known or
    /// broken, or the link was asked less than `lineageWait` ago. Marks it asked.
    public mutating func lineageRequest(forCard id: String, now: Date) -> String? {
        guard let card = pending[id], card.kind == .permission, card.sessionCoverable,
              case .missing(let missing) = walk(from: card.sessionID, grants: []),
              shouldAsk(missing, now: now) else { return nil }
        return missing
    }

    /// Approves every pending coverable permission card whose chain now reaches a
    /// grant (spec 8, "el barrido cubre el árbol"), except `requestID`: the card
    /// being clicked, which the app answers itself. A card with an unknown
    /// lineage stays, and its missing link is asked.
    public mutating func sweep(settings: Settings, now: Date, excluding requestID: String? = nil) -> [OpenCodeAction] {
        var actions = releaseHeld(settings: settings, now: now) { $0.entry.deadline <= now }
        guard !settings.sessionGrants.isEmpty else { return actions }
        for card in pending.values.sorted(by: { $0.id < $1.id }) {
            guard card.kind == .permission, card.sessionCoverable, card.id != requestID else { continue }
            switch walk(from: card.sessionID, grants: settings.sessionGrants) {
            case .granted:
                pending.removeValue(forKey: card.id)
                let log = AutoLogEntry(ts: now.timeIntervalSince1970, agent: "opencode", project: card.project,
                                       cwd: card.cwd, tool: card.tool, hint: String(card.hint.prefix(200)),
                                       category: card.category, grant: "session", session: card.sessionID)
                actions.append(.autoReply(sessionID: card.sessionID, requestID: card.id, log: log))
                actions.append(.withdrawCard(id: card.id))
            case .missing(let missing):
                if shouldAsk(missing, now: now) {
                    actions.append(.resolveLineage(sessionID: missing))
                }
            case .root, .broken:
                break
            }
        }
        return actions
    }

    /// Climbs from `sessionID` (checked first) through its known parents.
    private func walk(from sessionID: String, grants: Set<String>) -> LineageWalk {
        var node = sessionID
        var seen: Set<String> = [node]
        var hops = 0
        while true {
            if grants.contains(node) { return .granted(node) }
            guard let link = lineage[node] else {
                // Only a well-formed id that still exists is worth a GET.
                if goneSessions.contains(node) || !SessionGrantStore.isValidSessionID(node) { return .broken }
                return .missing(node)
            }
            guard case .child(let parent) = link else { return .root(node) }
            hops += 1
            if hops > Self.lineageDepthLimit || !seen.insert(parent).inserted { return .broken }
            node = parent
        }
    }

    /// False when `sessionID` was asked less than `lineageWait` ago; otherwise marks it asked now.
    private mutating func shouldAsk(_ sessionID: String, now: Date) -> Bool {
        if let asked = lineageAsked[sessionID], now.timeIntervalSince(asked) < Self.lineageWait { return false }
        lineageAsked[sessionID] = now
        return true
    }

    // MARK: - Permissions

    private mutating func handlePermission(_ request: OpenCodePermissionRequest, directory: String?,
                                           settings: Settings, now: Date) -> [OpenCodeAction] {
        if let directory { sessionDirectories[request.sessionID] = directory }
        guard !handled.contains(request.id),
              !held.contains(where: { $0.entry.request.id == request.id }) else { return [] }
        return judge(HeldRequest(request: request, directory: directory,
                                 deadline: now.addingTimeInterval(Self.lineageWait)),
                     settings: settings, now: now, mayWait: true)
    }

    /// Today's decision first; when it is a card, the request is coverable and a
    /// grant is in play, the session grant. `mayWait` false turns an unknown
    /// lineage into a card instead of holding the request again.
    private mutating func judge(_ entry: HeldRequest, settings: Settings, now: Date, mayWait: Bool) -> [OpenCodeAction] {
        let request = entry.request
        let dir = entry.directory ?? sessionDirectories[request.sessionID] ?? ""
        let toolInput = request.callID.flatMap { toolInputs[ToolInputKey(sessionID: request.sessionID, callID: $0)] }
        let context = RuleContext(cwd: dir, paths: settings.paths)
        let (subject, assessment) = OpenCodeRule.assess(request, toolInput: toolInput, directory: dir, context: context)

        var decision = AutoModePolicy.decide(subject: subject, assessment: assessment, autoMode: settings.autoMode,
                                             allowList: settings.allowList, cwd: dir, planMode: false)
        let coverable = AutoModePolicy.sessionGrantCovers(subject: subject, assessment: assessment)
        let chain = settings.sessionGrants.isEmpty ? nil : walk(from: request.sessionID, grants: settings.sessionGrants)

        if decision.verdict != .pass, coverable, let chain {
            switch chain {
            case .granted:
                decision = AutoModePolicy.decide(subject: subject, assessment: assessment, autoMode: settings.autoMode,
                                                 allowList: settings.allowList, cwd: dir, planMode: false,
                                                 sessionGrant: true)
            case .missing(let missing) where mayWait:
                held.append((entry, missing))
                return shouldAsk(missing, now: now) ? [.resolveLineage(sessionID: missing)] : []
            default:
                break
            }
        }
        handled.insert(request.id)
        var touch: [OpenCodeAction] = []
        if case .granted(let holder)? = chain { touch = [.touchSessionGrant(sessionID: holder)] }

        let project = (dir as NSString).lastPathComponent
        let fullHint = Self.hintText(for: request, toolInput: toolInput)
        if decision.verdict == .pass {
            let log = AutoLogEntry(ts: now.timeIntervalSince1970, agent: "opencode", project: project, cwd: dir,
                                   tool: request.action, hint: String(fullHint.prefix(200)),
                                   category: assessment.category.rawValue,
                                   grant: decision.grant == .session ? "session" : "auto",
                                   session: request.sessionID)
            return [.autoReply(sessionID: request.sessionID, requestID: request.id, log: log)] + touch
        }

        let (hint, hidden) = Self.clip(fullHint)
        let card = OpenCodeCardRequest(id: request.id, sessionID: request.sessionID, kind: .permission,
                                       tool: request.action, hint: hint, hidden: hidden, project: project,
                                       cwd: dir, category: assessment.category.rawValue,
                                       critical: assessment.critical, reason: assessment.reason, choices: nil,
                                       sessionCoverable: coverable)
        pending[request.id] = card
        return [.showCard(card)] + touch
    }

    /// An answer from opencode's own prompt. A held request never had a card:
    /// drop it into `handled` rather than withdraw one that was never shown.
    private mutating func replyReceived(_ requestID: String) -> [OpenCodeAction] {
        if held.contains(where: { $0.entry.request.id == requestID }) {
            held.removeAll { $0.entry.request.id == requestID }
            handled.insert(requestID)
            return []
        }
        return withdraw(requestID)
    }

    // MARK: - Held requests

    /// The held requests `release` picks become what today's rule says — a
    /// card, unless auto mode or "siempre permitir" passes them — never a
    /// pass by a grant: their lineage stayed unknown. In arrival order.
    private mutating func releaseHeld(settings: Settings, now: Date,
                                      _ release: ((entry: HeldRequest, missing: String)) -> Bool) -> [OpenCodeAction] {
        guard !held.isEmpty else { return [] }
        let leaving = held.filter(release)
        held.removeAll(where: release)
        var plain = settings
        plain.sessionGrants = []
        return leaving.flatMap { judge($0.entry, settings: plain, now: now, mayWait: false) }
    }

    /// After a parent became known: every held request is judged again, keeping
    /// its deadline. One whose chain is still cut waits for the next link.
    private mutating func revisitHeld(settings: Settings, now: Date) -> [OpenCodeAction] {
        let waiting = held
        held = []
        return waiting.flatMap { judge($0.entry, settings: settings, now: now, mayWait: true) }
    }

    /// Pending coverable cards climb one more link, so their root is known when clicked.
    private mutating func askNextLinks(now: Date) -> [OpenCodeAction] {
        var actions: [OpenCodeAction] = []
        for card in pending.values.sorted(by: { $0.id < $1.id }) where card.kind == .permission && card.sessionCoverable {
            if case .missing(let missing) = walk(from: card.sessionID, grants: []), shouldAsk(missing, now: now) {
                actions.append(.resolveLineage(sessionID: missing))
            }
        }
        return actions
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
