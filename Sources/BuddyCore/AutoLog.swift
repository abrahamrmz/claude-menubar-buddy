import Darwin
import Foundation

/// One auto-mode decision, as recorded for the history view. It also carries
/// the lifecycle of a session grant: turn-on and turn-off lines are logged
/// with category "concesion".
public struct AutoLogEntry: Codable, Equatable {
    public let ts: Double
    public let agent: String
    public let project: String
    public let cwd: String
    public let tool: String
    public let hint: String
    public let category: String
    /// "auto" | "session" | "concesion"; nil on lines written before grants.
    public let grant: String?
    public let session: String?

    public init(ts: Double, agent: String, project: String, cwd: String,
                tool: String, hint: String, category: String,
                grant: String? = nil, session: String? = nil) {
        self.ts = ts
        self.agent = agent
        self.project = project
        self.cwd = cwd
        self.tool = tool
        self.hint = hint
        self.category = category
        self.grant = grant
        self.session = session
    }
}

/// Why a session grant ended, as the history line says it.
public enum GrantEnd: String {
    case sessionEnded = "fin de sesión"
    case menu = "menú"
    case idle = "8 h sin actividad"
    case all = "todas"
}

extension AutoLogEntry {
    public static func grantStarted(_ grant: SessionGrant, ts: Double) -> AutoLogEntry {
        grantEvent(grant, hint: "encendida: \(grant.trigger)", ts: ts)
    }

    public static func grantEnded(_ grant: SessionGrant, cause: GrantEnd, ts: Double) -> AutoLogEntry {
        grantEvent(grant, hint: "apagada: \(cause.rawValue)", ts: ts)
    }

    private static func grantEvent(_ grant: SessionGrant, hint: String, ts: Double) -> AutoLogEntry {
        AutoLogEntry(ts: ts, agent: grant.agent, project: grant.project, cwd: grant.cwd,
                     tool: "sesión", hint: hint, category: "concesion",
                     grant: "concesion", session: grant.sessionID)
    }
}

/// Append-only log of what auto mode waved through. Best effort by design:
/// the hook must never fail because its notebook is full or locked.
public enum AutoLog {
    public static let fileName = "auto_decisions.jsonl"
    public static let rotatedName = "auto_decisions.1.jsonl"

    public static func append(_ entry: AutoLogEntry, in directory: URL, maxBytes: Int = 1_000_000) {
        let file = directory.appendingPathComponent(fileName)
        let rotated = directory.appendingPathComponent(rotatedName)
        let manager = FileManager.default

        if let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int,
           size >= maxBytes {
            try? manager.removeItem(at: rotated)
            try? manager.moveItem(at: file, to: rotated)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)

        // One `write(2)` on an O_APPEND descriptor: concurrent hooks each
        // append a whole line, never half of one.
        let descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard descriptor >= 0 else { return }
        _ = data.withUnsafeBytes { buffer in
            write(descriptor, buffer.baseAddress, buffer.count)
        }
        close(descriptor)
    }
}
