import Foundation

/// The shell half of the rule: what a command does, judged segment by
/// segment, and where it writes.
public enum ShellRule {
    public static func assess(_ command: String, context: RuleContext) -> Assessment {
        // Nothing to approve blindly.
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Assessment(.desconocido, "la regla no reconoce: ")
        }
        let script = ShellScript.parse(command)
        if script.unparseable || script.hasCaseStatement {
            return Assessment(.desconocido, "no se pudo analizar el comando")
        }
        if script.definesFunction {
            return Assessment(.desconocido, "define funciones de shell")
        }

        var state = RuleState(dir: context.cwd, dirKnown: !context.cwd.isEmpty, context: context)
        var worst: Assessment?
        for simple in script.commands {
            let input = CommandInput(words: simple.words,
                                     redirects: simple.redirects,
                                     subshellDepth: simple.subshellDepth)
            worst = worse(worst, evaluate(input, state: &state))
        }
        return worst ?? Assessment(.lectura, "solo lee")
    }

    // MARK: - One simple command

    /// The directory later segments are resolved against, and whether it is
    /// still trustworthy. A `cd` into a variable makes every following
    /// relative write unknowable, which must never read as "plain".
    struct RuleState {
        var dir: String
        var dirKnown: Bool
        let context: RuleContext
    }

    struct CommandInput {
        var words: [ShellWord]
        var redirects: [ShellRedirect]
        var subshellDepth: Int
    }

    struct WriteTarget {
        var word: ShellWord
        var overwrites: Bool
    }

    static func evaluate(_ input: CommandInput, state: inout RuleState) -> Assessment {
        var words = input.words

        var leadingAssignments: [String] = []
        while let first = words.first, let name = assignmentName(first.text) {
            leadingAssignments.append(name)
            words.removeFirst()
        }
        for name in leadingAssignments where changesCommandResolution(name) {
            return Assessment(.ejecuta, "cambia cómo se resuelve el comando: \(name)=")
        }
        // An assignment in front changes which binary the next word finds, so
        // it can never be waved through on the strength of that word alone.
        let hadCommandWord = !words.isEmpty

        if let wrapped = unwrap(&words) { return wrapped }

        var result = Assessment(.lectura, "solo lee")
        var targets: [WriteTarget] = []
        var protectedOnly: [ShellWord] = []

        if let head = words.first {
            result = assessHead(head, arguments: Array(words.dropFirst()),
                                subshellDepth: input.subshellDepth, state: &state,
                                targets: &targets, protectedOnly: &protectedOnly)
        }

        for redirect in input.redirects {
            guard redirect.kind == .write || redirect.kind == .append,
                  let target = redirect.target else { continue }
            targets.append(WriteTarget(word: target, overwrites: redirect.kind == .write))
        }

        if let origins = reviewProtectedOrigins(protectedOnly, state: state) {
            result = worse(result, origins)!
        }
        if let writes = reviewWrites(targets, state: state) {
            result = worse(result, writes)!
        }
        if let reads = reviewSensitiveReads(words, redirects: input.redirects, state: state) {
            result = worse(result, reads)!
        }

        if !leadingAssignments.isEmpty, hadCommandWord, !result.critical {
            result = worse(result, Assessment(.desconocido, "asignación de entorno antes del comando"))!
        }
        return result
    }

    private static func assessHead(_ head: ShellWord, arguments: [ShellWord], subshellDepth: Int,
                                   state: inout RuleState,
                                   targets: inout [WriteTarget],
                                   protectedOnly: inout [ShellWord]) -> Assessment {
        if head.expands || head.substitutes {
            return Assessment(.desconocido, "la regla no reconoce: \(short(head.text))")
        }
        let original = head.text
        if original.contains("deploy") {
            return Assessment(.sale, "sale de tu máquina: \(short(original))")
        }
        if original.hasPrefix("./") || original.hasPrefix("../") {
            return Assessment(.ejecuta, "ejecuta código: \(short(original))")
        }

        var name = original
        if name.contains("/") {
            let expanded = expandTilde(original, home: state.context.paths.home)
            let folder = (expanded as NSString).deletingLastPathComponent
            guard CommandCatalog.systemBinDirs.contains(folder) else {
                return Assessment(.ejecuta, "ejecuta código: \(short(original))")
            }
            name = (expanded as NSString).lastPathComponent
        }
        if [".sh", ".py", ".rb", ".js", ".ts", ".pl", "manage.py"].contains(where: { name.hasSuffix($0) }) {
            return Assessment(.ejecuta, "ejecuta código: \(short(original))")
        }

        switch name {
        case "cd", "pushd":
            updateDirectory(arguments, subshellDepth: subshellDepth, state: &state)
            return Assessment(.lectura, "solo lee")
        case "popd":
            state.dirKnown = false
            return Assessment(.lectura, "solo lee")
        case "defaults":
            return arguments.first?.text == "read"
                ? Assessment(.lectura, "solo lee")
                : Assessment(.ejecuta, "ejecuta código: \(short(original))")
        default:
            break
        }

        switch name {
        case "sed":
            return assessSed(arguments, state: state, targets: &targets, protectedOnly: &protectedOnly)
        case "find":
            return assessFind(arguments, state: state)
        default:
            break
        }

        if CommandCatalog.read.contains(name) {
            return assessReader(name, original: original, arguments: arguments)
        }
        if CommandCatalog.execute.contains(name) || CommandCatalog.isPython(name) {
            return Assessment(.ejecuta, "ejecuta código: \(short(original))")
        }
        if CommandCatalog.external.contains(name) {
            return Assessment(.sale, "sale de tu máquina: \(short(original))")
        }
        if CommandCatalog.irreversible.contains(name) {
            return Assessment(.irreversible, "no se puede deshacer: \(short(original))")
        }
        if CommandCatalog.localChange.contains(name) {
            collectLocalChangeTargets(name, arguments: arguments,
                                      targets: &targets, protectedOnly: &protectedOnly)
            return Assessment(.cambioLocal, "cambio local")
        }
        return Assessment(.desconocido, "la regla no reconoce: \(short(original))")
    }

    private static func assessReader(_ name: String, original: String,
                                     arguments: [ShellWord]) -> Assessment {
        let unknown = Assessment(.desconocido, "la regla no reconoce: \(short(original))")
        if ["export", "declare", "typeset", "local", "readonly"].contains(name) {
            for argument in arguments {
                if let assigned = assignmentName(argument.text), changesCommandResolution(assigned) {
                    return Assessment(.ejecuta, "cambia cómo se resuelve el comando: \(assigned)=")
                }
            }
            return Assessment(.lectura, "solo lee")
        }
        if ["sort", "tree"].contains(name), arguments.contains(where: { $0.text == "-o" }) {
            return unknown
        }
        if name == "yq", arguments.contains(where: { $0.text == "-i" }) {
            return unknown
        }
        if name == "uniq", nonFlagArguments(arguments).count >= 2 {
            return unknown
        }
        return Assessment(.lectura, "solo lee")
    }

    private static func updateDirectory(_ arguments: [ShellWord], subshellDepth: Int,
                                        state: inout RuleState) {
        guard let destination = arguments.first else {
            state.dir = state.context.paths.home
            if subshellDepth > 0 { state.dirKnown = false }
            return
        }
        if destination.expands || destination.substitutes || destination.text == "-" {
            state.dirKnown = false
            return
        }
        if let resolved = resolve(destination.text, state: state) {
            state.dir = resolved
        } else {
            state.dirKnown = false
        }
        if subshellDepth > 0 { state.dirKnown = false }
    }

    // MARK: - Write destinations

    private static func collectLocalChangeTargets(_ name: String, arguments: [ShellWord],
                                                  targets: inout [WriteTarget],
                                                  protectedOnly: inout [ShellWord]) {
        let nonFlags = nonFlagArguments(arguments)
        switch name {
        case "cp", "mv", "ln", "install":
            if let index = arguments.firstIndex(where: { $0.text == "-t" }) {
                let next = arguments.index(after: index)
                if next < arguments.endIndex {
                    targets.append(WriteTarget(word: arguments[next], overwrites: true))
                }
            } else if let destination = nonFlags.last {
                targets.append(WriteTarget(word: destination, overwrites: true))
            }
            // Moving a file out of a protected place is also a write there.
            if name == "mv" { protectedOnly.append(contentsOf: nonFlags.dropLast()) }
        case "tee":
            let appends = arguments.contains { $0.text == "-a" }
            for argument in nonFlags {
                targets.append(WriteTarget(word: argument, overwrites: !appends))
            }
        case "mkdir", "touch":
            for argument in nonFlags {
                targets.append(WriteTarget(word: argument, overwrites: false))
            }
        case "chmod", "chown", "chgrp":
            for argument in arguments.dropFirst() where !argument.text.hasPrefix("-") {
                targets.append(WriteTarget(word: argument, overwrites: false))
            }
        default:
            break
        }
    }

    // MARK: - Reviews

    static func reviewWrites(_ targets: [WriteTarget], state: RuleState) -> Assessment? {
        var worst: Assessment?
        for target in targets {
            if isIgnoredDevice(target.word.text) { continue }
            if target.word.expands || target.word.substitutes {
                worst = worse(worst, Assessment(.desconocido, "no se puede saber dónde escribe"))
                continue
            }
            guard let absolute = resolve(target.word.text, state: state) else {
                worst = worse(worst, Assessment(.desconocido, "no se puede saber dónde escribe"))
                continue
            }
            let path = state.context.paths.canonicalize(absolute)
            if state.context.paths.isProtected(path) {
                worst = worse(worst, Assessment(.rutaProtegida, "escribe en una ruta protegida: \(path)"))
                continue
            }
            if state.context.paths.isSensitive(path) {
                worst = worse(worst, Assessment(.sensible, "toca un archivo sensible: \(path)"))
                continue
            }
            if target.overwrites, state.context.paths.overwriteIsUnrecoverable(path) {
                worst = worse(worst, Assessment(.sobrescribe, "sobrescribe un archivo fuera de git: \(path)"))
                continue
            }
            worst = worse(worst, Assessment(.cambioLocal, "cambio local"))
        }
        return worst
    }

    static func reviewProtectedOrigins(_ words: [ShellWord], state: RuleState) -> Assessment? {
        var worst: Assessment?
        for word in words {
            guard !word.expands, !word.substitutes,
                  let absolute = resolve(word.text, state: state) else { continue }
            let path = state.context.paths.canonicalize(absolute)
            if state.context.paths.isProtected(path) {
                worst = worse(worst, Assessment(.rutaProtegida, "escribe en una ruta protegida: \(path)"))
            }
        }
        return worst
    }

    static func reviewSensitiveReads(_ words: [ShellWord], redirects: [ShellRedirect],
                                     state: RuleState) -> Assessment? {
        var candidates: [ShellWord] = []
        for word in words.dropFirst() {
            if word.text.hasPrefix("-") {
                if let equals = word.text.firstIndex(of: "=") {
                    candidates.append(ShellWord(text: String(word.text[word.text.index(after: equals)...]),
                                                expands: word.expands,
                                                substitutes: word.substitutes,
                                                quoted: word.quoted))
                }
                continue
            }
            candidates.append(word)
        }
        for redirect in redirects where redirect.kind == .read {
            if let target = redirect.target { candidates.append(target) }
        }

        for candidate in candidates {
            guard !candidate.expands, !candidate.substitutes else { continue }
            let path = state.context.paths.canonicalize(resolveForRead(candidate.text, state: state))
            if state.context.paths.isSensitive(path) {
                return Assessment(.sensible, "toca un archivo sensible: \(path)")
            }
        }
        return nil
    }

    // MARK: - Paths

    static func resolve(_ raw: String, state: RuleState) -> String? {
        if raw == "~" { return state.context.paths.home }
        if raw.hasPrefix("~/") { return state.context.paths.home + raw.dropFirst(1) }
        if raw.hasPrefix("/") { return raw }
        guard state.dirKnown else { return nil }
        let base = state.dir.isEmpty ? "/" : state.dir
        return base + "/" + raw
    }

    /// Reads still have a best guess when the directory is unknown: compare
    /// the name as if it were at the root, so a bare `.env` cannot hide.
    static func resolveForRead(_ raw: String, state: RuleState) -> String {
        if raw == "~" { return state.context.paths.home }
        if raw.hasPrefix("~/") { return state.context.paths.home + raw.dropFirst(1) }
        if raw.hasPrefix("/") { return raw }
        let base = state.dirKnown && !state.dir.isEmpty ? state.dir : "/"
        return base + "/" + raw
    }

    private static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    private static func isIgnoredDevice(_ text: String) -> Bool {
        if ["/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty"].contains(text) { return true }
        return text.hasPrefix("/dev/fd/")
    }

    // MARK: - Wrappers and words

    /// Strips the prefixes that only forward to another command. `sudo` does
    /// not forward innocently, so it stops here.
    private static func unwrap(_ words: inout [ShellWord]) -> Assessment? {
        wrapperLoop: while let head = words.first?.text {
            switch head {
            case "sudo", "doas":
                return Assessment(.ejecuta, "ejecuta con sudo")
            case "time":
                words.removeFirst()
                if words.first?.text == "-p" { words.removeFirst() }
            case "nohup":
                words.removeFirst()
            case "nice":
                words.removeFirst()
                if words.first?.text == "-n" {
                    words.removeFirst()
                    if !words.isEmpty { words.removeFirst() }
                } else if let flag = words.first?.text,
                          flag.range(of: "^-[0-9]+$", options: .regularExpression) != nil {
                    words.removeFirst()
                }
            case "timeout":
                words.removeFirst()
                while let flag = words.first?.text, flag.hasPrefix("-") { words.removeFirst() }
                if !words.isEmpty { words.removeFirst() }
            case "command":
                words.removeFirst()
                if words.first?.text == "-p" { words.removeFirst() }
            case "builtin":
                words.removeFirst()
            case "env":
                words.removeFirst()
                while let flag = words.first?.text {
                    if flag == "-i" {
                        words.removeFirst()
                    } else if flag == "-u" {
                        words.removeFirst()
                        if !words.isEmpty { words.removeFirst() }
                    } else if flag.hasPrefix("-u"), flag.count > 2 {
                        words.removeFirst()
                    } else {
                        break
                    }
                }
                while let first = words.first, let name = assignmentName(first.text) {
                    if changesCommandResolution(name) {
                        return Assessment(.ejecuta, "cambia cómo se resuelve el comando: \(name)=")
                    }
                    words.removeFirst()
                }
            default:
                break wrapperLoop
            }
        }
        return nil
    }

    private static func nonFlagArguments(_ words: [ShellWord]) -> [ShellWord] {
        words.filter { !$0.text.hasPrefix("-") }
    }

    static func assignmentName(_ text: String) -> String? {
        guard let range = text.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) else {
            return nil
        }
        return String(text[range].dropLast())
    }

    static func changesCommandResolution(_ name: String) -> Bool {
        name == "PATH" || name.hasPrefix("DYLD_") || name.hasPrefix("LD_") || name.hasPrefix("GIT_")
    }

    // MARK: - Helpers

    static func worse(_ a: Assessment?, _ b: Assessment?) -> Assessment? {
        guard let a else { return b }
        guard let b else { return a }
        return b.category.severity > a.category.severity ? b : a
    }

    static func short(_ text: String) -> String {
        String(text.prefix(40))
    }
}
