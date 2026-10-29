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

    public init(_ category: RuleCategory, _ reason: String) {
        self.category = category
        self.reason = reason
    }

    public var critical: Bool { category.isCritical }
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
