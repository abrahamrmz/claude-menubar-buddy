import Foundation

/// What the rule decided about one thing the user's session wants to do.
public enum RuleCategory: String, Codable, CaseIterable {
    case lectura
    case cambioLocal = "cambio_local"
    case edicion
    case ejecuta
    case irreversible
    case sale
    case rutaProtegida = "ruta_protegida"
    case sensible
    case sobrescribe
    case pregunta
    case desconocido

    /// Critical means: a card always, and no auto-approval, whatever mode.
    public var isCritical: Bool {
        switch self {
        case .ejecuta, .irreversible, .sale, .rutaProtegida, .sensible: return true
        default: return false
        }
    }

    /// The categories auto mode may wave through without a card.
    public var passesInAutoMode: Bool {
        switch self {
        case .lectura, .cambioLocal, .edicion: return true
        default: return false
        }
    }

    /// Higher wins when one command holds several segments. The order is the
    /// one the spec fixed: critical over unknown over overwrite over changes.
    public var severity: Int {
        switch self {
        case .ejecuta, .irreversible, .sale, .rutaProtegida, .sensible: return 4
        case .desconocido, .pregunta: return 3
        case .sobrescribe: return 2
        case .cambioLocal, .edicion: return 1
        case .lectura: return 0
        }
    }
}

public struct Assessment: Equatable {
    public let category: RuleCategory
    public let reason: String
    /// Why a session grant does not cover this. Auto mode and "always allow" never read it.
    /// Never stored for `.sale` or `.rutaProtegida`: there the reason already is the hold.
    public let sessionHold: String?

    public init(_ category: RuleCategory, _ reason: String, sessionHold: String? = nil) {
        self.category = category
        self.reason = reason
        self.sessionHold = Self.holdsByItself(category) ? nil : sessionHold
    }

    public var critical: Bool { category.isCritical }

    /// sessionHold, or the reason itself when the category is .sale or .rutaProtegida.
    public var effectiveHold: String? {
        Self.holdsByItself(category) ? reason : sessionHold
    }

    /// The same assessment with sessionHold set; an existing sessionHold is kept.
    public func holding(_ why: String) -> Assessment {
        effectiveHold != nil ? self : Assessment(category, reason, sessionHold: why)
    }

    /// Same winner as today's ShellRule.worse (higher severity; on a tie the first wins).
    /// The winner keeps its own sessionHold, or inherits the loser's effectiveHold.
    public static func worse(_ a: Assessment?, _ b: Assessment?) -> Assessment? {
        guard let a else { return b }
        guard let b else { return a }
        let (winner, loser) = b.category.severity > a.category.severity ? (b, a) : (a, b)
        guard let inherited = loser.effectiveHold else { return winner }
        return winner.holding(inherited)
    }

    private static func holdsByItself(_ category: RuleCategory) -> Bool {
        category == .sale || category == .rutaProtegida
    }
}

public struct RuleContext {
    /// Absolute, or empty when the session's directory is unknown.
    public var cwd: String
    public var paths: PathPolicy

    public init(cwd: String, paths: PathPolicy) {
        self.cwd = cwd
        self.paths = paths
    }
}
