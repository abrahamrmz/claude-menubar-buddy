import Foundation

/// One thing an agent wants to do, translated from whatever tool name the
/// agent uses. The rule reasons about the subject, not the tool.
public enum RuleSubject: Equatable {
    case shell(command: String)
    case fileEdit(path: String)
    case web(tool: String)
    case question(tool: String)
    case other(tool: String)

    public static func fromClaudeHook(toolName: String, toolInput: [String: Any]) -> RuleSubject {
        switch toolName {
        case "Bash":
            return .shell(command: toolInput["command"] as? String ?? "")
        case "Edit", "MultiEdit", "Write":
            return .fileEdit(path: toolInput["file_path"] as? String ?? "")
        case "NotebookEdit":
            return .fileEdit(path: toolInput["notebook_path"] as? String ?? "")
        case "WebFetch", "WebSearch":
            return .web(tool: toolName)
        case "AskUserQuestion", "ExitPlanMode":
            return .question(tool: toolName)
        default:
            return .other(tool: toolName)
        }
    }
}

public enum CommandRule {
    public static func assess(_ subject: RuleSubject, context: RuleContext) -> Assessment {
        switch subject {
        case .shell(let command):
            return ShellRule.assess(command, context: context)
        case .fileEdit(let path):
            return assessFileEdit(path, context: context)
        case .web(let tool):
            return Assessment(.sale, "sale de tu máquina: \(tool)")
        case .question(let tool):
            return tool == "ExitPlanMode"
                ? Assessment(.pregunta, "plan propuesto")
                : Assessment(.pregunta, "pregunta del agente")
        case .other(let tool):
            return Assessment(.desconocido, "la regla no reconoce: \(tool)")
        }
    }

    private static func assessFileEdit(_ path: String, context: RuleContext) -> Assessment {
        // An edit lands wherever its path says, so an unknown path can only
        // be an unknown decision.
        guard !path.isEmpty, path.hasPrefix("/"),
              !path.split(separator: "/").contains("..") else {
            return Assessment(.desconocido, "no se puede saber dónde cae: \(path)")
        }
        let canonical = context.paths.canonicalize(path)
        if context.paths.isProtected(canonical) {
            return Assessment(.rutaProtegida, "escribe en una ruta protegida: \(canonical)")
        }
        if context.paths.isSensitive(canonical) {
            return Assessment(.sensible, "toca un archivo sensible: \(canonical)")
        }
        return Assessment(.edicion, "edición de archivo")
    }
}
