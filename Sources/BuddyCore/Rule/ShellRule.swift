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
        /// Links an earlier `ln` on this line is about to create: where the
        /// link will be (canonical spelling) → what it will point at.
        var madeLinks: [String: String] = [:]
        /// The links of the command being judged right now. They count from
        /// the next command on: making a link does not write through it.
        var pendingLinks: [String: String] = [:]
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
        if !state.pendingLinks.isEmpty {
            state.madeLinks.merge(state.pendingLinks) { _, newer in newer }
            state.pendingLinks.removeAll()
        }
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

        if let network = reviewNetworkRedirects(input.redirects) {
            result = worse(result, network)!
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

        // A reader with an option that names a program is already execution.
        if let option = assessExecutionOptions(name, arguments: arguments) {
            return option
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
        case "git":
            return assessGit(arguments, state: state, targets: &targets)
        case "gh":
            return assessGh(arguments)
        case "ssh":
            return assessSSH(arguments, state: state)
        case "awk", "gawk", "nawk":
            return assessAwk(arguments)
        case "xargs":
            return assessXargs(arguments, state: state)
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
            if ["cp", "mv", "ln", "install"].contains(name) {
                appendLandingTargets(arguments, state: state, targets: &targets)
            }
            if name == "ln" {
                let linked = reviewLinkSources(arguments, state: state)
                noteMadeLinks(arguments, state: &state)
                if let linked { return linked }
            }
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
            let paths = state.context.paths
            let reached = reaches(absolute, state: state)
            if let hit = reached.lazy.compactMap(paths.protectedSpelling).first {
                worst = worse(worst, Assessment(.rutaProtegida,
                                                "escribe en una ruta protegida: \(PathPolicy.label(reached[0], landingOn: hit))"))
                continue
            }
            if let hit = reached.lazy.compactMap(paths.sensitiveSpelling).first {
                worst = worse(worst, Assessment(.sensible,
                                                "toca un archivo sensible: \(PathPolicy.label(reached[0], landingOn: hit))"))
                continue
            }
            if target.overwrites, let lost = reached.first(where: paths.overwriteIsUnrecoverable) {
                worst = worse(worst, Assessment(.sobrescribe, "sobrescribe un archivo fuera de git: \(lost)"))
                continue
            }
            worst = worse(worst, Assessment(.cambioLocal, "cambio local"))
        }
        return worst
    }

    /// Bash's `/dev/tcp` and `/dev/udp` are sockets, not files: a redirect
    /// there takes data off the machine while looking like a write.
    static func reviewNetworkRedirects(_ redirects: [ShellRedirect]) -> Assessment? {
        for redirect in redirects
        where redirect.kind == .write || redirect.kind == .append || redirect.kind == .read {
            guard let target = redirect.target else { continue }
            if target.text.hasPrefix("/dev/tcp/") || target.text.hasPrefix("/dev/udp/") {
                return Assessment(.sale, "abre una conexión de red: \(target.text)")
            }
        }
        return nil
    }

    static func reviewProtectedOrigins(_ words: [ShellWord], state: RuleState) -> Assessment? {
        var worst: Assessment?
        for word in words {
            guard !word.expands, !word.substitutes,
                  let absolute = resolve(word.text, state: state) else { continue }
            let reached = reaches(absolute, state: state)
            if let hit = reached.lazy.compactMap(state.context.paths.protectedSpelling).first {
                worst = worse(worst, Assessment(.rutaProtegida,
                                                "escribe en una ruta protegida: \(PathPolicy.label(reached[0], landingOn: hit))"))
            }
        }
        return worst
    }

    // MARK: - Links made on this line

    /// The spellings to judge for `absolute`: the path as written and, when an
    /// earlier `ln` on this line turns part of it into a link, where that
    /// leads. Never empty; the first is always the path as written.
    static func reaches(_ absolute: String, state: RuleState) -> [String] {
        let paths = state.context.paths
        var found = [paths.canonicalize(absolute)]
        if let through = throughMadeLinks(absolute, state: state) {
            let other = paths.canonicalize(through)
            if other != found[0] { found.append(other) }
        }
        return found
    }

    /// Reads `absolute` as if the links this line has already made were on
    /// disk; nil when none of them is on the way.
    ///
    /// The path policy follows links by asking the disk, and the rule runs
    /// before the command does. `ln -s ~ h && echo x >> h/.gitconfig` names
    /// nothing protected until `h` exists — so each component is checked
    /// against what the line itself is about to create, before any `..` is
    /// collapsed: `d/../x` leaves through wherever `d` points.
    static func throughMadeLinks(_ absolute: String, state: RuleState) -> String? {
        guard !state.madeLinks.isEmpty else { return nil }
        let paths = state.context.paths
        var pending = absolute.split(separator: "/").map(String.init)
        var walked = ""
        var index = 0
        var hops = 0
        var changed = false
        while index < pending.count {
            let next = walked + "/" + pending[index]
            if hops < 16, let target = state.madeLinks[paths.canonicalize(next)] {
                pending = target.split(separator: "/").map(String.init) + pending[(index + 1)...]
                walked = ""
                index = 0
                hops += 1
                changed = true
                continue
            }
            walked = next
            index += 1
        }
        guard changed else { return nil }
        return walked.isEmpty ? "/" : walked
    }

    private static func makesSymbolicLinks(_ arguments: [ShellWord]) -> Bool {
        arguments.contains { flag in
            flag.text == "--symbolic" || (flag.text.hasPrefix("-") && !flag.text.hasPrefix("--") && flag.text.contains("s"))
        }
    }

    /// GNU's `-t dir` puts the receiving folder first instead of last.
    private static func namesItsFolderFirst(_ arguments: [ShellWord]) -> Bool {
        arguments.contains { flag in
            flag.text.hasPrefix("--target-directory")
                || (flag.text.hasPrefix("-") && !flag.text.hasPrefix("--") && flag.text.contains("t"))
        }
    }

    private static func isRelative(_ text: String) -> Bool {
        !text.hasPrefix("/") && text != "~" && !text.hasPrefix("~/")
    }

    /// The last name of what a word points at: `~` is the home folder's name.
    private static func landingName(_ word: ShellWord, state: RuleState) -> String? {
        let spelled = isRelative(word.text) ? word.text : (resolve(word.text, state: state) ?? word.text)
        let name = (spelled as NSString).lastPathComponent
        return name.isEmpty || name == "/" || name == "." || name == ".." ? nil : name
    }

    /// Whether `destination` receives files rather than being replaced by one.
    private static func isFolder(_ destination: ShellWord, among count: Int, state: RuleState) -> Bool {
        if destination.text.hasSuffix("/") || count > 2 { return true }
        guard let absolute = resolve(destination.text, state: state) else { return false }
        return reaches(absolute, state: state).contains(where: state.context.paths.probe.isDirectory)
    }

    /// Remembers what `ln` is about to create, so the rest of the line is
    /// read as if the link were already there (`throughMadeLinks`).
    private static func noteMadeLinks(_ arguments: [ShellWord], state: inout RuleState) {
        let nonFlags = nonFlagArguments(arguments)
        guard !nonFlags.isEmpty, !namesItsFolderFirst(arguments),
              !nonFlags.contains(where: { $0.expands || $0.substitutes }) else { return }
        let symbolic = makesSymbolicLinks(arguments)
        let sources = nonFlags.count >= 2 ? Array(nonFlags.dropLast()) : nonFlags

        // Where the links land: inside a folder, under their own names, or
        // as the one name given. With a single word they land right here.
        var folder: String?
        var single: String?
        if nonFlags.count >= 2, let destination = nonFlags.last {
            guard let absolute = resolve(destination.text, state: state) else { return }
            if isFolder(destination, among: nonFlags.count, state: state) { folder = absolute } else { single = absolute }
        } else {
            guard state.dirKnown else { return }
            folder = state.dir.isEmpty ? "/" : state.dir
        }

        for source in sources {
            let link: String
            if let single {
                link = single
            } else if let folder, let name = landingName(source, state: state) {
                link = folder + "/" + name
            } else {
                continue
            }
            // The text of a symbolic link is read from the folder it lives in.
            let target = symbolic && isRelative(source.text)
                ? (link as NSString).deletingLastPathComponent + "/" + source.text
                : resolve(source.text, state: state)
            if let target { state.pendingLinks[state.context.paths.canonicalize(link)] = target }
        }
    }

    /// `cp tool dir` writes `dir/tool`. When the destination is a folder, the
    /// file that lands in it is what gets written, so it is judged as well:
    /// `cp tmp/.gitconfig ~` replaces `~/.gitconfig`.
    private static func appendLandingTargets(_ arguments: [ShellWord], state: RuleState,
                                             targets: inout [WriteTarget]) {
        let nonFlags = nonFlagArguments(arguments)
        guard nonFlags.count >= 2, !namesItsFolderFirst(arguments), let destination = nonFlags.last,
              !destination.expands, !destination.substitutes,
              isFolder(destination, among: nonFlags.count, state: state) else { return }
        var folder = destination.text
        while folder.count > 1 && folder.hasSuffix("/") { folder.removeLast() }
        for source in nonFlags.dropLast() where !source.expands && !source.substitutes {
            guard let name = landingName(source, state: state) else { continue }
            let landed = ShellWord(text: folder == "/" ? "/" + name : folder + "/" + name,
                                   expands: false, substitutes: false, quoted: destination.quoted)
            targets.append(WriteTarget(word: landed, overwrites: true))
        }
    }

    /// A link is a second name for what it points at: once it exists, writing
    /// to the new name writes there, and reading it reads there. The path
    /// policy follows links that are already on disk, but the rule runs
    /// before the command does — in `ln -s ~/.zshrc x && echo y >> x` there
    /// is no `x` yet to follow. So the link is judged here, when it is made,
    /// by what it will point at. That covers hard links too, which leave
    /// nothing to follow afterwards.
    static func reviewLinkSources(_ arguments: [ShellWord], state: RuleState) -> Assessment? {
        let nonFlags = nonFlagArguments(arguments)
        let symbolic = makesSymbolicLinks(arguments)
        // `ln a b`: b is the link. `ln a b dir/`: the links land in dir. With
        // one name alone the link lands here, so there is no other folder to
        // read its text from. GNU's `-t dir` puts the folder first instead;
        // rather than guess which word is which, every one is judged.
        let namesItsFolder = namesItsFolderFirst(arguments)
        let sources = namesItsFolder || nonFlags.count < 2 ? nonFlags : Array(nonFlags.dropLast())
        let destination = namesItsFolder || nonFlags.count < 2 ? nil : nonFlags.last
        let paths = state.context.paths

        var worst: Assessment?
        for source in sources {
            if source.expands || source.substitutes {
                worst = worse(worst, Assessment(.desconocido, "no se puede saber a dónde apunta el enlace"))
                continue
            }
            var candidates: [String] = []
            if let fromHere = resolve(source.text, state: state) { candidates.append(fromHere) }
            // The text of a symbolic link is read from the folder the link
            // lives in, not from here: `ln -s ../../.gitconfig sub/g` points
            // two folders above `sub`. The destination may be the link or the
            // folder that receives it, so both are tried.
            if symbolic, isRelative(source.text), let destination, !destination.expands, !destination.substitutes,
               let landing = resolve(destination.text, state: state) {
                candidates.append(landing + "/" + source.text)
                candidates.append((landing as NSString).deletingLastPathComponent + "/" + source.text)
            }
            if candidates.isEmpty {
                worst = worse(worst, Assessment(.desconocido, "no se puede saber a dónde apunta el enlace"))
                continue
            }
            for candidate in candidates {
                let reached = reaches(candidate, state: state)
                if let hit = reached.lazy.compactMap(paths.protectedSpelling).first {
                    worst = worse(worst, Assessment(.rutaProtegida,
                                                    "enlaza una ruta protegida: \(PathPolicy.label(reached[0], landingOn: hit))"))
                } else if let hit = reached.lazy.compactMap(paths.sensitiveSpelling).first {
                    worst = worse(worst, Assessment(.sensible,
                                                    "enlaza un archivo sensible: \(PathPolicy.label(reached[0], landingOn: hit))"))
                }
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
            let reached = reaches(resolveForRead(candidate.text, state: state), state: state)
            if let hit = reached.lazy.compactMap(state.context.paths.sensitiveSpelling).first {
                return Assessment(.sensible, "toca un archivo sensible: \(PathPolicy.label(reached[0], landingOn: hit))")
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
    static func unwrap(_ words: inout [ShellWord]) -> Assessment? {
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
                while let flag = words.first?.text, flag.hasPrefix("-") {
                    if ["-s", "-k", "--signal", "--kill-after"].contains(flag) {
                        words.removeFirst()
                        if !words.isEmpty { words.removeFirst() }
                    } else if flag.hasPrefix("--signal=") || flag.hasPrefix("--kill-after=")
                                || (flag.hasPrefix("-s") && flag.count > 2)
                                || (flag.hasPrefix("-k") && flag.count > 2) {
                        words.removeFirst()
                    } else {
                        words.removeFirst()
                    }
                }
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
        dangerousAssignmentNames.contains(name)
            || name.hasPrefix("DYLD_") || name.hasPrefix("LD_") || name.hasPrefix("GIT_")
    }

    /// Variables that change what the next command *is*, not just how it
    /// looks: a PATH-like name in front of a command is already execution.
    static let dangerousAssignmentNames: Set<String> = [
        "PATH", "BASH_ENV", "ENV", "ZDOTDIR", "PROMPT_COMMAND",
    ]

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
