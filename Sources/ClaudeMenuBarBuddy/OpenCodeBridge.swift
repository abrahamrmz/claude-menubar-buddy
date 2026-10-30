import AppKit
import BuddyCore
import Foundation

// The app's half of the opencode bridge: a connection to the local opencode
// service, and the side effects the pure core (OpenCodeBridgeCore) asks for.
// Events arrive over one SSE stream; answers leave over HTTP. Nothing here
// decides anything — the rule, the auto mode and the queue all run in
// BuddyCore, so this file is only transport plus a few files on disk, in the
// exact shape the app already reads for Claude (request_<id>.json, done_<sid>.json).
//
// The password from service.json never leaves OpenCodeService: it goes into
// the Authorization header of each URLRequest and nowhere else. No DebugLog
// line ever carries it.
final class OpenCodeBridge: NSObject, URLSessionDataDelegate {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case unavailable(String)
    }

    private(set) var state: State = .idle {
        didSet {
            // The health check reads this; the password and URL never do.
            switch state {
            case .idle: BuddyHealth.openCodeState = nil
            case .connecting: BuddyHealth.openCodeState = "connecting"
            case .connected: BuddyHealth.openCodeState = "connected"
            case .unavailable(let reason): BuddyHealth.openCodeState = "unavailable: \(reason)"
            }
        }
    }

    private let configDir: URL
    private var core = OpenCodeBridgeCore()
    private var service: OpenCodeService?
    // The event stream has its own delegate-based session; every other call
    // goes through the plain one, so the delegate callbacks are unambiguously
    // about the stream. Lazy so it can name `self` as its delegate.
    private lazy var streamSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 7 * 24 * 3600
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    private let apiSession: URLSession
    private var streamTask: URLSessionDataTask?
    private var sse = SSEParser()
    private var retryDelay: TimeInterval = 1
    private var retryWorkItem: DispatchWorkItem?
    private var stopped = false

    init(configDir: URL) {
        self.configDir = configDir
        let apiConfig = URLSessionConfiguration.default
        apiConfig.timeoutIntervalForRequest = 30
        self.apiSession = URLSession(configuration: apiConfig)
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        stopped = false
        guard streamTask == nil, retryWorkItem == nil else { return }
        connect()
    }

    func stop() {
        stopped = true
        retryWorkItem?.cancel()
        retryWorkItem = nil
        let task = streamTask
        streamTask = nil
        task?.cancel()
        state = .idle
    }

    private func connect() {
        state = .connecting
        guard let svc = OpenCodeService.load(from: OpenCodeService.defaultFile) else {
            state = .unavailable("opencode no está corriendo")
            scheduleReconnect()
            return
        }
        service = svc
        sse = SSEParser()
        let task = streamSession.dataTask(with: OpenCodeCall.events.urlRequest(service: svc))
        streamTask = task
        task.resume()
    }

    /// 1, 2, 4, 8, 16, 30, 30… seconds. Reset to 1 by a successful connection.
    private func scheduleReconnect() {
        guard !stopped else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        retryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.retryWorkItem = nil
            self?.connect()
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - URLSessionDataDelegate (the event stream only)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 200 {
            retryDelay = 1
            state = .connected
            recover()
        } else {
            DebugLog.note("opencode event stream: HTTP \(code)")
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        for body in sse.feed(data) {
            if let event = OpenCodeEvent.decode(body) { handle(event) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard streamTask === task else { return }
        streamTask = nil
        guard !stopped else { return }
        if let error {
            DebugLog.note("opencode event stream ended: \(error.localizedDescription)")
        } else {
            DebugLog.note("opencode event stream closed")
        }
        state = .connecting
        scheduleReconnect()
    }

    // MARK: - Events → actions

    private func handle(_ event: OpenCodeEvent) {
        for action in core.handle(event, settings: currentSettings(), now: Date()) {
            perform(action)
        }
    }

    /// Built per event, the way the hook builds its own rule context. launchd
    /// starts the app with a minimal PATH, so the usual bin directories are
    /// appended before the path policy reads it — otherwise a command found
    /// through them would not have its directory treated as protected.
    private func currentSettings() -> OpenCodeBridgeCore.Settings {
        let autoMode = FileManager.default.fileExists(atPath: configDir.appendingPathComponent("auto_mode").path)
        let allowList = AlwaysAllow.read(from: configDir.appendingPathComponent("always_allow.json"))
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/bin"]
        let base = env["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = ([base] + extras).joined(separator: ":")
        let paths = PathPolicy.fromEnvironment(env, probe: LiveFileProbe())
        return OpenCodeBridgeCore.Settings(autoMode: autoMode, allowList: allowList, paths: paths)
    }

    private func perform(_ action: OpenCodeAction) {
        switch action {
        case .autoReply(let sessionID, let requestID, let log):
            send(.replyPermission(sessionID: sessionID, requestID: requestID, decision: "once", message: nil))
            AutoLog.append(log, in: configDir)

        case .showCard(let card):
            // A permission may have been answered in opencode's terminal
            // between the event and the card; the short delay lets that land
            // first, then the pending check decides (opencode bug #47545).
            // Forms have no such check — the event is the only notice.
            if card.kind == .permission {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.confirmPermissionStillPending(card)
                }
            } else {
                writeRequestFile(card)
            }

        case .withdrawCard(let id):
            removeRequestFile(id)

        case .turnFinished(let sessionID, let elapsed):
            confirmTurn(sessionID: sessionID, elapsed: elapsed)
        }
    }

    private func confirmPermissionStillPending(_ card: OpenCodeCardRequest) {
        send(.permissionStillPending(sessionID: card.sessionID, requestID: card.id)) { [weak self] code, _ in
            guard let self else { return }
            if code == 200 {
                self.writeRequestFile(card)
            } else {
                // Answered in the terminal: drop it so a later reconnect
                // doesn't bring the card back.
                self.core.forget(id: card.id)
            }
        }
    }

    private func confirmTurn(sessionID: String, elapsed: Int) {
        send(.session(id: sessionID)) { [weak self] code, data in
            guard let self, code == 200, let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let session = (root["data"] as? [String: Any]) ?? root
            // A subagent's turn is not the user's turn: no toast for it.
            if let parent = session["parentID"], !(parent is NSNull) { return }
            let directory = (session["location"] as? [String: Any])?["directory"] as? String ?? ""
            let marker: [String: Any] = [
                "project": (directory as NSString).lastPathComponent,
                "elapsed": elapsed,
                "ts": Date().timeIntervalSince1970,
                "agent": "opencode",
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: marker) else { return }
            try? body.write(to: self.configDir.appendingPathComponent("done_\(sessionID).json"),
                            options: [.atomic])
        }
    }

    // MARK: - Recovery on (re)connect

    /// A fresh connection knows nothing about what happened while it was
    /// away, so it re-asks: every session touched in the last day has its
    /// pending permissions and forms turned back into events. An id already
    /// known is not duplicated — the core's `handled` set takes care of it.
    private func recover() {
        send(.sessions(limit: 20)) { [weak self] code, data in
            guard let self, code == 200, let data, let sessions = Self.array(from: data) else { return }
            let cutoff = Date().timeIntervalSince1970 * 1000 - 24 * 60 * 60 * 1000
            for session in sessions {
                guard let id = session["id"] as? String else { continue }
                if let updated = (session["time"] as? [String: Any])?["updated"] as? Double, updated < cutoff { continue }
                let directory = (session["location"] as? [String: Any])?["directory"] as? String
                self.recoverPending(sessionID: id, directory: directory)
            }
        }
    }

    private func recoverPending(sessionID: String, directory: String?) {
        send(.pendingPermissions(sessionID: sessionID)) { [weak self] code, data in
            guard let self, code == 200, let data, let items = Self.array(from: data) else { return }
            for item in items { self.deliver(type: "permission.asked", directory: directory, data: item) }
        }
        send(.pendingForms(sessionID: sessionID)) { [weak self] code, data in
            guard let self, code == 200, let data, let items = Self.array(from: data) else { return }
            for item in items { self.deliver(type: "form.created", directory: directory, data: ["form": item]) }
        }
    }

    /// Rebuilds the event envelope the live stream would have sent, so the
    /// same `OpenCodeEvent.decode` handles a recovered request.
    private func deliver(type: String, directory: String?, data: [String: Any]) {
        var wrapper: [String: Any] = ["type": type, "data": data]
        if let directory { wrapper["location"] = ["directory": directory] }
        guard let json = try? JSONSerialization.data(withJSONObject: wrapper),
              let text = String(data: json, encoding: .utf8),
              let event = OpenCodeEvent.decode(text) else { return }
        handle(event)
    }

    private static func array(from data: Data) -> [[String: Any]]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let root = object as? [String: Any] { return root["data"] as? [[String: Any]] }
        return object as? [[String: Any]]
    }

    // MARK: - Answering a card

    /// The card's decision for an opencode request. Called by writeDecision
    /// instead of writing response_<id>.json: opencode answers over HTTP.
    func answer(id: String, decision: String, reason: String?, answers: [String: String]?) {
        guard let card = core.pending(id: id) else { return }
        if let call = OpenCodeAnswer.call(for: card, decision: decision, reason: reason, answers: answers) {
            // A 404 means somebody answered first (the terminal, another
            // window): there is nothing left to reply to, and no error.
            send(call) { code, _ in
                if code != 200 && code != 204 && code != 404 {
                    DebugLog.note("opencode reply for \(id) → HTTP \(code)")
                }
            }
        }
        removeRequestFile(id)
        core.forget(id: id)
    }

    // MARK: - HTTP

    /// Runs one call off the main thread and hands the result back on it.
    /// Errors are logged by call type and status only — never the password or
    /// the Authorization header.
    private func send(_ call: OpenCodeCall, completion: ((Int, Data?) -> Void)? = nil) {
        guard let service else { return }
        let request = call.urlRequest(service: service)
        apiSession.dataTask(with: request) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let error {
                DebugLog.note("opencode \(Self.label(call)) failed: \(error.localizedDescription)")
            } else if code >= 400 {
                DebugLog.note("opencode \(Self.label(call)) → HTTP \(code)")
            }
            guard let completion else { return }
            DispatchQueue.main.async { completion(code, data) }
        }.resume()
    }

    /// A short name for the log line. Deliberately not the whole call: the
    /// description would echo the reply body, which is fine, but a stable
    /// label keeps the flight recorder readable.
    private static func label(_ call: OpenCodeCall) -> String {
        switch call {
        case .events: return "events"
        case .sessions: return "sessions"
        case .session: return "session"
        case .pendingPermissions: return "pendingPermissions"
        case .pendingForms: return "pendingForms"
        case .permissionStillPending: return "permissionStillPending"
        case .replyPermission: return "replyPermission"
        case .replyForm: return "replyForm"
        }
    }

    // MARK: - Files

    private func writeRequestFile(_ card: OpenCodeCardRequest) {
        let url = configDir.appendingPathComponent("request_\(card.id).json")
        try? card.requestFileJSON(now: Date()).write(to: url, options: [.atomic])
    }

    private func removeRequestFile(_ id: String) {
        try? FileManager.default.removeItem(at: configDir.appendingPathComponent("request_\(id).json"))
    }
}
