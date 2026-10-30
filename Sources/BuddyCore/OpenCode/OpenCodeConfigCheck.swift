import Foundation

/// Whether opencode is configured to ask the buddy before it runs a shell
/// command or edits a file. Its config is JSONC (comments and trailing commas
/// allowed), so this reads it the way opencode does before looking at the rules.
public enum OpenCodeConfigCheck {
    /// The effect opencode ends up with for `action` on resource "*": the last rule whose action is that action
    /// (or "*") and whose resource is exactly "*". nil when no such rule exists — opencode then allows.
    public static func effect(of action: String, inConfig text: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(stripJSONC(text).utf8)),
              let dict = object as? [String: Any],
              let permissions = dict["permissions"] as? [[String: Any]] else { return nil }
        var result: String?
        for rule in permissions {
            guard let ruleAction = rule["action"] as? String,
                  let resource = rule["resource"] as? String,
                  resource == "*",
                  ruleAction == action || ruleAction == "*" else { continue }
            if let effect = rule["effect"] as? String { result = effect }
        }
        return result
    }

    /// True when both "shell" and "edit" end at "ask".
    public static func asksForShellAndEdit(configText: String) -> Bool {
        effect(of: "shell", inConfig: configText) == "ask"
            && effect(of: "edit", inConfig: configText) == "ask"
    }

    // MARK: - JSONC

    /// JSON with comments and trailing commas removed, so `JSONSerialization`
    /// can read it. The scan tracks string state so a `//` or `/*` inside a
    /// value (`"http://x"`, a Windows path) stays text, and respects `\"`.
    private static func stripJSONC(_ text: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i += 1
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                i += 2
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i < chars.count && !(chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/") { i += 1 }
                if i < chars.count { i += 2 }
                continue
            }
            out.append(c)
            i += 1
        }
        return removeTrailingCommas(out)
    }

    /// Drops a `,` that is followed only by whitespace and then `}` or `]`.
    private static func removeTrailingCommas(_ text: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i += 1
                continue
            }
            if c == "," {
                var j = i + 1
                while j < chars.count && chars[j].isWhitespace { j += 1 }
                if j < chars.count && (chars[j] == "}" || chars[j] == "]") {
                    i += 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return out
    }
}
