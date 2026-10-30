import Foundation

/// The local opencode service, as advertised in `service.json`.
public struct OpenCodeService: Equatable {
    public let baseURL: URL
    public let password: String

    public init(baseURL: URL, password: String) {
        self.baseURL = baseURL
        self.password = password
    }

    public static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state/opencode/service.json")
    }

    /// nil when the file is missing or unreadable, or the URL isn't http on 127.0.0.1, localhost or ::1.
    ///
    /// The loopback-only rule is the whole point: `service.json` is a file on
    /// disk, so anything that can write it could point the buddy at a remote
    /// host. The buddy only ever talks to the opencode running on this machine.
    public static func load(from file: URL) -> OpenCodeService? {
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              let urlText = dict["url"] as? String, !urlText.isEmpty,
              let password = dict["password"] as? String, !password.isEmpty,
              let url = URL(string: urlText),
              url.scheme == "http",
              let host = url.host,
              ["127.0.0.1", "localhost", "::1"].contains(host) else { return nil }
        return OpenCodeService(baseURL: url, password: password)
    }

    public var authorization: String {
        "Basic " + Data("opencode:\(password)".utf8).base64EncodedString()
    }
}

/// One HTTP call the bridge can make. Kept as data so the app layer only has
/// to execute it, and the tests can check every URL and body exactly.
public enum OpenCodeCall: Equatable {
    case events
    case sessions(limit: Int)
    case session(id: String)
    case pendingPermissions(sessionID: String)
    case pendingForms(sessionID: String)
    case permissionStillPending(sessionID: String, requestID: String)
    case replyPermission(sessionID: String, requestID: String, decision: String, message: String?)
    case replyForm(sessionID: String, formID: String, answer: [String: String])

    public func urlRequest(service: OpenCodeService) -> URLRequest {
        switch self {
        case .events:
            return make(service, method: "GET", path: "/api/event",
                        headers: ["Accept": "text/event-stream"])
        case .sessions(let limit):
            return make(service, method: "GET", path: "/api/session",
                        query: [URLQueryItem(name: "limit", value: String(limit)),
                                URLQueryItem(name: "order", value: "desc")])
        case .session(let id):
            return make(service, method: "GET", path: "/api/session/\(id)")
        case .pendingPermissions(let sessionID):
            return make(service, method: "GET", path: "/api/session/\(sessionID)/permission")
        case .pendingForms(let sessionID):
            return make(service, method: "GET", path: "/api/session/\(sessionID)/form")
        case .permissionStillPending(let sessionID, let requestID):
            return make(service, method: "GET", path: "/api/session/\(sessionID)/permission/\(requestID)")
        case .replyPermission(let sessionID, let requestID, let decision, let message):
            var body: [String: Any] = ["decision": decision]
            if let message { body["message"] = message }
            return make(service, method: "POST", path: "/api/session/\(sessionID)/permission/\(requestID)/reply",
                        body: body)
        case .replyForm(let sessionID, let formID, let answer):
            return make(service, method: "POST", path: "/api/session/\(sessionID)/form/\(formID)/reply",
                        body: ["answer": answer])
        }
    }

    private func make(_ service: OpenCodeService, method: String, path: String,
                      query: [URLQueryItem] = [], body: [String: Any]? = nil,
                      headers: [String: String] = [:]) -> URLRequest {
        var components = URLComponents(url: service.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(service.authorization, forHTTPHeaderField: "Authorization")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        return request
    }
}

/// What a card decision means for opencode. The buddy never replies `always`:
/// the "siempre permitir" list is its own, and opencode must keep asking.
public enum OpenCodeAnswer {
    /// What a card decision means for opencode. nil = no call: the opencode terminal keeps its own prompt.
    public static func call(for card: OpenCodeCardRequest, decision: String, reason: String?,
                            answers: [String: String]?) -> OpenCodeCall? {
        switch card.kind {
        case .permission:
            switch decision {
            case "allow":
                return .replyPermission(sessionID: card.sessionID, requestID: card.id,
                                        decision: "once", message: nil)
            case "deny":
                // A reject without a message makes opencode drop the session's
                // other pending requests too, so there is always one.
                return .replyPermission(sessionID: card.sessionID, requestID: card.id,
                                        decision: "reject",
                                        message: reason ?? "El usuario lo rechazó desde el buddy.")
            default:
                return nil
            }
        case .form:
            guard decision == "answer", let choices = card.choices else { return nil }
            var answer: [String: String] = [:]
            for choice in choices {
                guard let label = answers?[choice.question],
                      let option = choice.options.first(where: { $0.label == label }) else { continue }
                answer[choice.fieldKey] = option.value
            }
            guard !answer.isEmpty else { return nil }
            return .replyForm(sessionID: card.sessionID, formID: card.id, answer: answer)
        }
    }
}
