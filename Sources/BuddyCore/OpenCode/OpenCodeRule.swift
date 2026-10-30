import Foundation

/// Translates one opencode permission request into the rule subjects it stands
/// for, so opencode is judged by the same rule as Claude Code.
public enum OpenCodeRule {
    /// The rule subjects one permission request stands for (one per file in a multi-file edit).
    public static func subjects(for request: OpenCodePermissionRequest, toolInput: [String: String]?,
                                directory: String) -> [RuleSubject] {
        switch request.action.lowercased() {
        case "shell":
            let command = toolInput?["command"] ?? request.resources.joined(separator: "; ")
            return [.shell(command: command)]
        case "edit":
            let paths: [String]
            if !request.editedFiles.isEmpty {
                paths = request.editedFiles
            } else if let path = toolInput?["path"], !path.isEmpty {
                paths = [path]
            } else {
                paths = request.resources
            }
            return paths.map { .fileEdit(path: absolute($0, in: directory)) }
        case "read":
            return request.resources.map { .fileRead(path: absolute($0, in: directory)) }
        case "webfetch", "websearch":
            return [.web(tool: request.action.lowercased())]
        case "question":
            return [.question(tool: "question")]
        default:
            return [.other(tool: request.action.lowercased())]
        }
    }

    /// The worst assessment over those subjects (highest severity, first wins on ties) and the
    /// subject it came from. An empty list is Assessment(.desconocido, "la regla no reconoce: ACTION").
    public static func assess(_ request: OpenCodePermissionRequest, toolInput: [String: String]?,
                              directory: String, context: RuleContext) -> (subject: RuleSubject, assessment: Assessment) {
        let mapped = subjects(for: request, toolInput: toolInput, directory: directory)
        let candidates = mapped.isEmpty ? [RuleSubject.other(tool: request.action.lowercased())] : mapped
        var best: (subject: RuleSubject, assessment: Assessment) = (candidates[0], CommandRule.assess(candidates[0], context: context))
        for subject in candidates.dropFirst() {
            let assessment = CommandRule.assess(subject, context: context)
            if assessment.category.severity > best.assessment.category.severity {
                best = (subject, assessment)
            }
        }
        return best
    }

    /// opencode names files relative to the session's directory; the rule needs an absolute path.
    private static func absolute(_ path: String, in directory: String) -> String {
        if path.hasPrefix("/") || directory.isEmpty { return path }
        return directory + "/" + path
    }
}
