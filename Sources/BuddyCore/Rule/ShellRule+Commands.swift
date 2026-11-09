import Foundation

// The tools that read like filters but can write or execute through their
// own arguments. A handler looks at what the arguments actually say; the
// generic write and sensitive-path reviews still run on top of its verdict.

extension ShellRule {
    // MARK: - Options that execute

    /// Some readers accept an option naming a program to run. The command
    /// still looks like `rg` or `sort`, so the name is not enough.
    static func assessExecutionOptions(_ name: String, arguments: [ShellWord]) -> Assessment? {
        let options: [String]
        switch name {
        case "rg":
            options = ["--pre"]
        case "sort":
            options = ["--compress-program"]
        case "bat":
            options = ["--pager"]
        case "zip":
            options = ["-TT", "--unzip-command"]
        default:
            return nil
        }
        for argument in arguments {
            for option in options
            where argument.text == option || argument.text.hasPrefix(option + "=") {
                return Assessment(.ejecuta, "ejecuta código a través de una opción: \(option)")
            }
        }
        return nil
    }

    // MARK: - sed

    static func assessSed(_ arguments: [ShellWord], state: RuleState,
                          targets: inout [WriteTarget],
                          protectedOnly: inout [ShellWord]) -> Assessment {
        var inPlace = false
        var scripts: [String] = []
        var files: [ShellWord] = []
        var sawScriptFlag = false
        var justEnabledInPlace = false

        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            let text = word.text

            if justEnabledInPlace {
                justEnabledInPlace = false
                // `sed -i '' …`: the empty backup suffix the BSD sed wants.
                if text.isEmpty {
                    index += 1
                    continue
                }
            }
            if text == "-f" || text.hasPrefix("-f") && text.count > 2 || text == "--file" {
                return Assessment(.desconocido, "la regla no reconoce: sed")
            }
            if text == "-i" || (text.hasPrefix("-i") && text.count > 2) || text == "--in-place" {
                inPlace = true
                justEnabledInPlace = true
                index += 1
                continue
            }
            if text.hasPrefix("--in-place=") {
                inPlace = true
                index += 1
                continue
            }
            if text == "-I" || (text.hasPrefix("-I") && text.count > 2) {
                inPlace = true
                index += 1
                continue
            }
            if text == "-e" || text == "--expression" {
                sawScriptFlag = true
                if index + 1 < arguments.count {
                    scripts.append(arguments[index + 1].text)
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if text.hasPrefix("--expression=") {
                sawScriptFlag = true
                scripts.append(String(text.dropFirst("--expression=".count)))
                index += 1
                continue
            }
            if text.hasPrefix("-e"), text.count > 2 {
                sawScriptFlag = true
                scripts.append(String(text.dropFirst(2)))
                index += 1
                continue
            }
            if text.hasPrefix("-") {
                index += 1
                continue
            }
            if !sawScriptFlag && scripts.isEmpty {
                scripts.append(text)
            } else {
                files.append(word)
            }
            index += 1
        }

        if scripts.contains(where: sedScriptWritesOrExecutes) {
            return Assessment(.ejecuta, "sed con comandos que escriben o ejecutan")
        }
        if inPlace {
            for file in files {
                targets.append(WriteTarget(word: file, overwrites: true))
            }
            return Assessment(.cambioLocal, "cambio local")
        }
        return Assessment(.lectura, "solo lee")
    }

    private static func sedScriptWritesOrExecutes(_ script: String) -> Bool {
        script.range(of: "(^|[;\n{}!/0-9$,\\s])[wWe]($|\\s)", options: .regularExpression) != nil
    }

    // MARK: - find

    static func assessFind(_ arguments: [ShellWord], state: RuleState) -> Assessment {
        var worst = Assessment(.lectura, "solo lee")
        var deletes = false
        var index = 0
        while index < arguments.count {
            switch arguments[index].text {
            case "-delete":
                deletes = true
                worst = worse(worst, Assessment(.irreversible, "no se puede deshacer: find"))!
                index += 1
            case "-exec", "-execdir", "-ok", "-okdir":
                var nested: [ShellWord] = []
                var cursor = index + 1
                while cursor < arguments.count,
                      arguments[cursor].text != ";" && arguments[cursor].text != "+" {
                    nested.append(arguments[cursor])
                    cursor += 1
                }
                if !nested.isEmpty {
                    if let first = nested.first, deleters.contains((first.text as NSString).lastPathComponent) {
                        deletes = true
                    }
                    var nestedState = state
                    worst = worse(worst, evaluate(CommandInput(words: nested, redirects: [],
                                                               subshellDepth: 0),
                                                  state: &nestedState))!
                }
                index = cursor + 1
            case "-fprint", "-fprint0", "-fprintf", "-fls":
                worst = worse(worst, Assessment(.desconocido, "la regla no reconoce: find",
                                                sessionHold: "escribe un archivo que la regla no revisa: find"))!
                index += 1
            default:
                index += 1
            }
        }
        if deletes {
            let roots = arguments.prefix { !$0.text.hasPrefix("-") && $0.text != "(" && $0.text != "!" }
            if let why = deletionHold(Array(roots), state: state) {
                worst = worst.holding(why)
            }
        }
        return worst
    }

    // MARK: - git

    /// Every push stays out of a session grant whatever else the line says
    /// (`git push --receive-pack=x` is `ejecuta`), and so does every git the
    /// rule doesn't know (spec 5.3 point 8).
    static func assessGit(_ arguments: [ShellWord], state: RuleState,
                          targets: inout [WriteTarget]) -> Assessment {
        let (result, subcommand) = gitAssessment(arguments, state: state, targets: &targets)
        if subcommand == "push" { return result.holding("sale de tu máquina: git push") }
        if result.category == .desconocido { return result.holding(result.reason) }
        return result
    }

    private static func gitAssessment(_ arguments: [ShellWord], state: RuleState,
                                      targets: inout [WriteTarget]) -> (Assessment, subcommand: String?) {
        var localState = state
        var index = 0
        var subcommand: String?
        var subArguments: [ShellWord] = []

        while index < arguments.count {
            let text = arguments[index].text

            if text == "-C" {
                if index + 1 < arguments.count {
                    let path = arguments[index + 1]
                    if !path.expands, !path.substitutes,
                       let resolved = resolve(path.text, state: localState) {
                        localState.dir = resolved
                        localState.dirKnown = true
                    } else {
                        localState.dirKnown = false
                    }
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            if text == "-c" || (text.hasPrefix("-c") && !text.hasPrefix("--")) {
                return (Assessment(.rutaProtegida, "git -c puede ejecutar código"), nil)
            }
            if ["--git-dir", "--work-tree", "--exec-path", "--namespace"].contains(text)
                || ["--git-dir=", "--work-tree=", "--exec-path=", "--namespace="].contains(where: { text.hasPrefix($0) }) {
                return (Assessment(.desconocido, "la regla no reconoce: git"), nil)
            }
            if ["--no-pager", "--paginate", "-p", "--bare", "--literal-pathspecs", "--no-optional-locks"].contains(text) {
                index += 1
                continue
            }
            if text.hasPrefix("-") {
                return (Assessment(.desconocido, "la regla no reconoce: git"), nil)
            }
            subcommand = text
            subArguments = Array(arguments[(index + 1)...])
            break
        }

        guard let subcommand else {
            return (Assessment(.desconocido, "la regla no reconoce: git"), nil)
        }

        // A transport can name a program of the caller's choosing.
        if subArguments.contains(where: { $0.text.hasPrefix("ext::") || $0.text.hasPrefix("fd::") }) {
            return (Assessment(.ejecuta, "ejecuta código a través de un transporte de git"), subcommand)
        }

        // Transport options can name the program git will run on either end.
        for word in subArguments {
            for option in ["--upload-pack", "--receive-pack", "--exec"]
            where word.text == option || word.text.hasPrefix(option + "=") {
                return (Assessment(.ejecuta, "ejecuta código a través de una opción: \(option)"), subcommand)
            }
        }
        if ["clone", "fetch", "pull", "ls-remote", "archive"].contains(subcommand),
           subArguments.contains(where: {
               $0.text == "-u" || ($0.text.hasPrefix("-u") && !$0.text.hasPrefix("--") && $0.text.count > 2)
           }) {
            return (Assessment(.ejecuta, "ejecuta código a través de una opción: -u"), subcommand)
        }

        var cursor = 0
        while cursor < subArguments.count {
            let word = subArguments[cursor]
            if word.text == "--output", cursor + 1 < subArguments.count, !subArguments[cursor + 1].text.hasPrefix("-") {
                targets.append(WriteTarget(word: subArguments[cursor + 1], overwrites: true))
                cursor += 2
                continue
            }
            if word.text.hasPrefix("--output=") {
                targets.append(WriteTarget(word: ShellWord(text: String(word.text.dropFirst("--output=".count)),
                                                           expands: word.expands,
                                                           substitutes: word.substitutes,
                                                           quoted: word.quoted),
                                           overwrites: true))
            }
            cursor += 1
        }

        return (assessGitSubcommand(subcommand, arguments: subArguments, state: localState), subcommand)
    }

    private static let gitReadSubcommands: Set<String> = [
        "status", "log", "diff", "show", "blame", "grep", "rev-parse", "ls-files", "ls-tree", "ls-remote",
        "describe", "shortlog", "fetch", "reflog", "cat-file", "merge-base", "rev-list", "name-rev",
        "check-ignore", "check-attr", "count-objects", "help", "version", "whatchanged", "show-ref",
        "for-each-ref", "var",
    ]

    private static let gitLocalChangeSubcommands: Set<String> = [
        "add", "commit", "switch", "merge", "pull", "rebase", "cherry-pick", "revert", "tag", "mv", "rm",
        "init", "clone", "notes", "bisect", "sparse-checkout",
    ]

    private static func assessGitSubcommand(_ subcommand: String, arguments: [ShellWord],
                                            state: RuleState) -> Assessment {
        if gitReadSubcommands.contains(subcommand) {
            if subcommand == "grep",
               arguments.contains(where: { $0.text == "-O" || $0.text == "--open-files-in-pager" }) {
                return Assessment(.ejecuta, "ejecuta código: git grep -O")
            }
            return Assessment(.lectura, "solo lee")
        }

        let nonFlags = arguments.filter { !$0.text.hasPrefix("-") }
        switch subcommand {
        case "restore", "clean":
            return Assessment(.irreversible, "no se puede deshacer: git \(subcommand)")
        case "push":
            return Assessment(.sale, "sale de tu máquina: git push")
        case "checkout":
            if arguments.contains(where: { $0.text == "--" }) {
                return Assessment(.irreversible, "no se puede deshacer: git checkout")
            }
            if arguments.contains(where: { ["-b", "-B", "--orphan"].contains($0.text) }) {
                return Assessment(.cambioLocal, "cambio local")
            }
            for argument in nonFlags {
                guard !argument.expands, !argument.substitutes,
                      let absolute = resolve(argument.text, state: state) else { continue }
                let path = state.context.paths.canonicalize(absolute)
                if argument.text == "." || state.context.paths.probe.exists(path) {
                    return Assessment(.irreversible, "no se puede deshacer: git checkout")
                }
            }
            return Assessment(.cambioLocal, "cambio local")
        case "reset":
            if arguments.contains(where: { $0.text == "--hard" }) {
                return Assessment(.irreversible, "no se puede deshacer: git reset --hard")
            }
            return Assessment(.cambioLocal, "cambio local")
        case "bisect":
            if arguments.first?.text == "run" {
                return Assessment(.ejecuta, "ejecuta código: git bisect run")
            }
            return Assessment(.cambioLocal, "cambio local")
        case "rebase":
            // `-x` is `--exec` in short form: a shell line per commit.
            if arguments.contains(where: { $0.text == "-x" || ($0.text.hasPrefix("-x") && $0.text.count > 2) }) {
                return Assessment(.ejecuta, "ejecuta código a través de una opción: -x")
            }
            return Assessment(.cambioLocal, "cambio local")
        case "stash":
            switch nonFlags.first?.text {
            case "list", "show":
                return Assessment(.lectura, "solo lee")
            case "drop", "clear":
                return Assessment(.irreversible, "no se puede deshacer: git stash")
            default:
                return Assessment(.cambioLocal, "cambio local")
            }
        case "branch":
            if arguments.contains(where: { $0.text == "-D" }) {
                return Assessment(.irreversible, "no se puede deshacer: git branch -D")
            }
            let listingFlags: Set<String> = [
                "-a", "-r", "-v", "-vv", "--list", "-l", "--show-current", "--all", "--remotes", "--verbose",
            ]
            if nonFlags.isEmpty && arguments.allSatisfy({ listingFlags.contains($0.text) }) {
                return Assessment(.lectura, "solo lee")
            }
            return Assessment(.cambioLocal, "cambio local")
        case "remote":
            if arguments.isEmpty { return Assessment(.lectura, "solo lee") }
            if arguments.count == 1, arguments[0].text == "-v" { return Assessment(.lectura, "solo lee") }
            if let action = arguments.first?.text, action == "show" || action == "get-url" {
                return Assessment(.lectura, "solo lee")
            }
            return Assessment(.rutaProtegida, "cambia .git/config")
        case "config":
            let readFlags: Set<String> = [
                "--get", "--get-all", "--get-regexp", "--list", "-l", "--show-origin", "--show-scope",
            ]
            if arguments.contains(where: { readFlags.contains($0.text) }) {
                return Assessment(.lectura, "solo lee")
            }
            return Assessment(.rutaProtegida, "cambia .git/config")
        case "worktree":
            switch nonFlags.first?.text {
            case "list":
                return Assessment(.lectura, "solo lee")
            case "remove", "prune":
                return Assessment(.irreversible, "no se puede deshacer: git worktree")
            default:
                return Assessment(.cambioLocal, "cambio local")
            }
        default:
            if gitLocalChangeSubcommands.contains(subcommand) {
                return Assessment(.cambioLocal, "cambio local")
            }
            return Assessment(.desconocido, "la regla no reconoce: git \(subcommand)")
        }
    }

    // MARK: - gh

    static func assessGh(_ arguments: [ShellWord]) -> Assessment {
        guard let first = arguments.first?.text else {
            return Assessment(.desconocido, "la regla no reconoce: gh")
        }
        let second = arguments.dropFirst().first?.text
        let sale = Assessment(.sale, "sale de tu máquina: gh \(first)\(second.map { " " + $0 } ?? "")")

        switch first {
        case "pr":
            if let second, ["view", "list", "diff", "checks", "status"].contains(second) {
                return Assessment(.lectura, "solo lee")
            }
            if second == "checkout" { return Assessment(.cambioLocal, "cambio local") }
            return sale
        case "issue":
            if let second, ["view", "list", "status"].contains(second) {
                return Assessment(.lectura, "solo lee")
            }
            return sale
        case "search":
            return Assessment(.lectura, "solo lee")
        case "repo":
            if let second, ["view", "list"].contains(second) {
                return Assessment(.lectura, "solo lee")
            }
            if second == "clone" {
                // Everything after `--` is handed to `git clone`, including the
                // options that name a program to run.
                if let separator = arguments.firstIndex(where: { $0.text == "--" }) {
                    for word in arguments[arguments.index(after: separator)...] {
                        for option in ["--upload-pack", "--receive-pack", "--exec"]
                        where word.text == option || word.text.hasPrefix(option + "=") {
                            return Assessment(.ejecuta, "ejecuta código a través de una opción: \(option)")
                        }
                        if word.text == "-u"
                            || (word.text.hasPrefix("-u") && !word.text.hasPrefix("--") && word.text.count > 2) {
                            return Assessment(.ejecuta, "ejecuta código a través de una opción: -u")
                        }
                    }
                }
                return Assessment(.cambioLocal, "cambio local")
            }
            return sale
        case "run":
            if let second, ["view", "list", "watch"].contains(second) {
                return Assessment(.lectura, "solo lee")
            }
            return sale
        case "release":
            if let second, ["view", "list"].contains(second) {
                return Assessment(.lectura, "solo lee")
            }
            return sale
        case "workflow":
            if let second, ["view", "list"].contains(second) {
                return Assessment(.lectura, "solo lee")
            }
            return sale
        case "auth":
            if second == "status" { return Assessment(.lectura, "solo lee") }
            return sale
        case "browse":
            return Assessment(.ejecuta, "ejecuta código: gh browse")
        default:
            return sale
        }
    }

    // MARK: - ssh

    private static let sshValueOptions: Set<String> = [
        "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l", "-m", "-O", "-o", "-p", "-Q",
        "-R", "-S", "-W", "-w", "-B", "-P",
    ]

    static func assessSSH(_ arguments: [ShellWord], state: RuleState) -> Assessment {
        // `-F` picks another config, and `-o` can name a local program.
        for index in arguments.indices {
            let text = arguments[index].text
            if text == "-F" || (text.hasPrefix("-F") && text.count > 2) {
                return Assessment(.ejecuta, "ejecuta código a través de una opción: -F",
                                  sessionHold: "ssh que no solo lee")
            }
            if text == "-o" {
                if index + 1 < arguments.count, dangerousSSHOption(arguments[index + 1].text) {
                    return Assessment(.ejecuta, "ejecuta código a través de una opción: -o",
                                      sessionHold: "ssh que no solo lee")
                }
            } else if text.hasPrefix("-o"), text.count > 2,
                      dangerousSSHOption(String(text.dropFirst(2))) {
                return Assessment(.ejecuta, "ejecuta código a través de una opción: -o",
                                  sessionHold: "ssh que no solo lee")
            }
        }

        var index = 0
        var host: String?
        var remoteWords: [ShellWord] = []
        var localExpansion: String?

        while index < arguments.count {
            let word = arguments[index]
            let text = word.text
            if host == nil {
                if text.hasPrefix("-"), text.count > 1 {
                    if sshValueOptions.contains(text) {
                        index += 2
                    } else if text.count > 2, sshValueOptions.contains(String(text.prefix(2))) {
                        index += 1
                    } else {
                        index += 1
                    }
                    continue
                }
                host = text
                index += 1
                continue
            }
            if word.expands || word.substitutes { localExpansion = "ssh con una expansión local" }
            remoteWords.append(word)
            index += 1
        }

        guard host != nil, !remoteWords.isEmpty else {
            return Assessment(.sale, "ssh interactivo")
        }

        let script = ShellScript.parse(remoteWords.map(\.text).joined(separator: " "))
        if script.unparseable || script.hasCaseStatement || script.definesFunction {
            return Assessment(.sale, "ssh que no solo lee")
        }

        let onlyReads = script.commands.allSatisfy { remoteSimpleIsRead($0, state: state) }
        let hold = onlyReads ? localExpansion : "ssh que no solo lee"

        for simple in script.commands {
            var candidates = simple.words.filter { !$0.text.hasPrefix("-") }
            for redirect in simple.redirects where redirect.kind == .read {
                if let target = redirect.target { candidates.append(target) }
            }
            for word in candidates {
                guard !word.expands, !word.substitutes else { continue }
                let path = word.text.hasPrefix("/") ? word.text : "/remote/" + word.text
                let canonical = state.context.paths.canonicalize(path)
                if state.context.paths.isSensitive(canonical) {
                    return Assessment(.sensible, "toca un archivo sensible: \(canonical)", sessionHold: hold)
                }
            }
        }

        if !onlyReads {
            return Assessment(.sale, "ssh que no solo lee")
        }
        return Assessment(.lectura, "ssh que solo lee", sessionHold: localExpansion)
    }

    private static func dangerousSSHOption(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return ["proxycommand", "localcommand", "permitlocalcommand", "knownhostscommand"].contains {
            lowered.contains($0)
        }
    }

    private static func remoteSimpleIsRead(_ simple: SimpleCommand, state: RuleState) -> Bool {
        for redirect in simple.redirects where redirect.kind == .write || redirect.kind == .append {
            if redirect.target?.text != "/dev/null" { return false }
        }

        var words = simple.words
        if unwrap(&words) != nil { return false }
        guard let head = words.first else { return true }
        if head.expands || head.substitutes { return false }

        let name = head.text
        if name.contains("/") {
            if name.hasPrefix("./") || name.hasPrefix("../") { return false }
            if !CommandCatalog.systemBinDirs.contains((name as NSString).deletingLastPathComponent) {
                return false
            }
        }
        let base = (name as NSString).lastPathComponent
        let arguments = Array(words.dropFirst())

        switch base {
        case "systemctl":
            guard let first = arguments.first?.text else { return false }
            return ["status", "is-active", "is-enabled", "list-units", "list-timers", "show", "cat"].contains(first)
        case "journalctl":
            return !arguments.contains {
                $0.text.hasPrefix("--vacuum") || $0.text == "--rotate" || $0.text == "--flush"
            }
        case "free", "w", "who", "last", "hostname", "ss", "netstat":
            return true
        case "docker":
            guard let first = arguments.first?.text else { return false }
            return ["ps", "logs", "inspect", "images", "stats"].contains(first)
        case "git":
            var targets: [WriteTarget] = []
            return assessGit(arguments, state: state, targets: &targets).category == .lectura
        case "sed":
            var targets: [WriteTarget] = []
            var protectedOnly: [ShellWord] = []
            return assessSed(arguments, state: state, targets: &targets,
                             protectedOnly: &protectedOnly).category == .lectura
        case "awk", "gawk", "nawk":
            return assessAwk(arguments).category == .lectura
        case "find":
            return assessFind(arguments, state: state).category == .lectura
        case "xargs":
            return assessXargs(arguments, state: state).category == .lectura
        default:
            if CommandCatalog.read.contains(base) {
                return !["export", "set", "pushd"].contains(base)
            }
            return false
        }
    }

    // MARK: - awk

    static func assessAwk(_ arguments: [ShellWord]) -> Assessment {
        if arguments.contains(where: { $0.text == "-f" || ($0.text.hasPrefix("-f") && $0.text.count > 2) }) {
            return Assessment(.desconocido, "la regla no reconoce: awk")
        }
        for argument in arguments {
            let text = argument.text
            if text.contains("system(") || text.contains("|") || text.contains("getline") {
                return Assessment(.ejecuta, "awk que ejecuta o escribe")
            }
            if text.range(of: "printf?[^;}]*>", options: .regularExpression) != nil {
                return Assessment(.ejecuta, "awk que ejecuta o escribe")
            }
        }
        return Assessment(.lectura, "solo lee")
    }

    // MARK: - xargs

    private static let xargsValueFlags: Set<Character> = ["n", "I", "P", "L", "s", "d", "E", "a"]

    static func assessXargs(_ arguments: [ShellWord], state: RuleState) -> Assessment {
        var index = 0
        while index < arguments.count {
            let text = arguments[index].text
            if text == "--" {
                index += 1
                break
            }
            guard text.hasPrefix("-"), text.count > 1 else { break }
            if text.hasPrefix("--") {
                index += 1
                continue
            }
            let flag = text[text.index(after: text.startIndex)]
            if text.count == 2, xargsValueFlags.contains(flag) {
                index += 2
            } else {
                index += 1
            }
        }

        let command = Array(arguments[min(index, arguments.count)...])
        guard !command.isEmpty else { return Assessment(.lectura, "solo lee") }
        var nestedState = state
        return evaluate(CommandInput(words: command, redirects: [], subshellDepth: 0),
                        state: &nestedState)
    }

    // MARK: - Session holds

    /// The commands that delete what they name (spec 5.3 point 7).
    static let deleters: Set<String> = ["rm", "rmdir", "unlink", "shred", "srm", "truncate"]

    /// What `rm` and its family would delete: every word that isn't a flag,
    /// and everything after `--`. For `dd`, the file after `of=`.
    static func deletionOperands(_ name: String, arguments: [ShellWord]) -> [ShellWord] {
        if name == "dd" {
            return arguments.compactMap { word in
                guard word.text.hasPrefix("of=") else { return nil }
                return ShellWord(text: String(word.text.dropFirst(3)), expands: word.expands,
                                 substitutes: word.substitutes, quoted: word.quoted)
            }
        }
        var operands: [ShellWord] = []
        var afterDoubleDash = false
        for word in arguments {
            if word.text == "--" { afterDoubleDash = true; continue }
            if afterDoubleDash || !word.text.hasPrefix("-") { operands.append(word) }
        }
        return operands
    }

    /// The first operand whose deletion a session grant must not cover, or nil
    /// when every one of them is ordinary (spec 5.3 point 7).
    static func deletionHold(_ operands: [ShellWord], state: RuleState) -> String? {
        for word in operands {
            if word.substitutes
                || (word.expands && word.text.contains("$"))
                || (word.text.hasPrefix("~") && word.text != "~" && !word.text.hasPrefix("~/")) {
                return "no se sabe qué borra: \(short(word.text))"
            }
            if word.expands {
                if let why = globDeletionHold(word.text, state: state) { return why }
                continue
            }
            guard let absolute = resolve(word.text, state: state) else {
                return "no se sabe qué borra: \(short(word.text))"
            }
            let reached = reaches(absolute, state: state)
            if let hit = reached.lazy.compactMap(state.context.paths.protectedSpelling).first {
                return "borra una ruta protegida: \(PathPolicy.label(reached[0], landingOn: hit))"
            }
            if let hit = reached.lazy.compactMap(state.context.paths.pinnedProtectedContainer).first {
                return "borra una carpeta que guarda rutas protegidas: \(PathPolicy.label(reached[0], landingOn: hit))"
            }
        }
        return nil
    }

    /// A deletion with a wildcard: dangerous when it can reach a hidden name,
    /// a protected folder, or a file the rule protects by name (spec 5.3 point 7).
    private static func globDeletionHold(_ text: String, state: RuleState) -> String? {
        let fixed = String(text.prefix { !"*?[".contains($0) })
        let folder: String
        let name: String
        if let slash = fixed.lastIndex(of: "/") {
            folder = String(fixed[...slash])
            name = String(fixed[fixed.index(after: slash)...])
        } else {
            folder = "."
            name = fixed
        }
        if name.hasPrefix(".") { return "borra con un comodín peligroso: \(text)" }
        guard let folderAbsolute = resolve(folder, state: state),
              let fullAbsolute = resolve(text, state: state) else {
            return "no se sabe qué borra: \(short(text))"
        }
        let reachedFolder = reaches(folderAbsolute, state: state)
        if reachedFolder.contains(where: { state.context.paths.protectedSpelling($0) != nil
                                            || state.context.paths.pinnedProtectedContainer($0) != nil }) {
            return "borra con un comodín peligroso: \(text)"
        }
        let paths = state.context.paths
        if reaches(fullAbsolute, state: state).contains(where: { paths.protectedSpelling($0) != nil }) {
            return "borra con un comodín peligroso: \(text)"
        }
        return nil
    }

    /// The holds that hang on a command's name and arguments rather than on
    /// its category. nil when a session grant may cover it. The first rule
    /// that holds wins (spec 5.3 points 10 to 13).
    static func commandHold(_ words: [ShellWord], input: CommandInput, headCategory: RuleCategory,
                            state: RuleState) -> String? {
        guard let head = words.first, !head.expands, !head.substitutes else { return nil }
        let name = (head.text as NSString).lastPathComponent
        let arguments = Array(words.dropFirst())
        if name == "sudo" || name == "doas" { return "usa \(name)" }
        if name == "alias" { return "define un alias" }
        // A line of shell inside this one is judged by what it says; its
        // arguments are that line, so the publishing words don't apply.
        if let inline = inlineShellHold(name, arguments: arguments, input: input, state: state) {
            return inline.hold
        }
        if CommandCatalog.sessionHeld.contains(name) || (name == "defaults" && arguments.first?.text != "read") {
            return "queda fuera del auto completo: \(name)"
        }
        if ["kill", "pkill", "killall"].contains(name), arguments.contains(where: namesTheBuddy) {
            return "puede detener al buddy"
        }
        if deleters.contains(name) || name == "dd",
           let why = deletionHold(deletionOperands(name, arguments: arguments), state: state) {
            return why
        }
        if let why = landingHold(name, arguments: arguments, state: state) { return why }
        if headCategory == .ejecuta || headCategory == .desconocido {
            return publishHold(arguments)
        }
        return nil
    }

    /// The first argument that names something that publishes, or a command
    /// that can take the line off the machine (spec 5.3 point 11).
    static func publishHold(_ arguments: [ShellWord]) -> String? {
        for argument in arguments {
            let lowered = argument.text.lowercased()
            if lowered == "--push" || lowered.hasPrefix("--push=") {
                return "puede publicar: --push"
            }
            if lowered.contains("deploy") || lowered.contains("publish") {
                return "puede publicar: \(argument.text)"
            }
            // A whole line can ride inside one argument (`watch 'git push'`);
            // splitting it is what makes those words visible.
            for token in lowered.split(whereSeparator: { " \t\n;|&()<>`'\"".contains($0) }) {
                guard !token.hasPrefix("-") else { continue }
                let word = String(token)
                if CommandCatalog.publishWords.contains(word) {
                    return "puede publicar: \(word)"
                }
                if CommandCatalog.external.contains(word) {
                    return "puede salir de tu máquina: \(word)"
                }
            }
        }
        return nil
    }

    // MARK: - Inline shells

    /// The interpreters whose arguments the rule reads as a line of shell.
    static let shells: Set<String> = ["bash", "sh", "zsh", "dash", "ksh", "fish", "csh", "tcsh"]

    /// A line of shell the command runs itself, and the hold that line carries
    /// (nil when the line only works here).
    struct InlineShell {
        var hold: String?
    }

    private static let unreadableInlineShell = "ejecuta un shell en línea que no se puede leer"

    /// nil when the command does not run a line of shell of its own; otherwise
    /// the hold of that line (possibly nil). `eval`, `exec` and the interpreters
    /// of `shells` carry one (spec 5.3 point 10).
    static func inlineShellHold(_ name: String, arguments: [ShellWord], input: CommandInput,
                                state: RuleState) -> InlineShell? {
        if name == "eval" {
            if arguments.contains(where: { $0.expands || $0.substitutes }) {
                return InlineShell(hold: unreadableInlineShell)
            }
            return InlineShell(hold: nestedHold(arguments.map(\.text).joined(separator: " "), state: state))
        }
        if name == "exec" {
            var rest = arguments
            while let first = rest.first, first.text.hasPrefix("-") {
                let flag = rest.removeFirst().text
                if flag == "-a", !rest.isEmpty { rest.removeFirst() }
            }
            if rest.isEmpty { return InlineShell(hold: nil) }
            var nestedState = state
            let result = evaluate(CommandInput(words: rest, redirects: input.redirects,
                                               subshellDepth: input.subshellDepth,
                                               heredocBody: input.heredocBody),
                                  state: &nestedState)
            return InlineShell(hold: result.effectiveHold)
        }
        guard shells.contains(name) else { return nil }

        var index = 0
        var executesText = false
        var readsInput = false
        var operand: ShellWord?
        while index < arguments.count {
            let word = arguments[index]
            let text = word.text
            if text == "--" {
                if index + 1 < arguments.count { operand = arguments[index + 1] }
                break
            }
            if text.hasPrefix("--") {
                if text == "--command" {
                    executesText = true
                    if index + 1 < arguments.count { operand = arguments[index + 1] }
                    break
                }
                if text.hasPrefix("--command=") {
                    executesText = true
                    operand = ShellWord(text: String(text.dropFirst("--command=".count)),
                                        expands: word.expands, substitutes: word.substitutes,
                                        quoted: word.quoted)
                    break
                }
                if text == "--rcfile" || text == "--init-file" {
                    index += 2
                    continue
                }
                index += 1
                continue
            }
            if (text.hasPrefix("-") || text.hasPrefix("+")) && text.count > 1 {
                let letters = text.dropFirst()
                if letters.contains("c") { executesText = true }
                if letters.contains("s") { readsInput = true }
                index += letters.contains("o") || letters.contains("O") ? 2 : 1
                continue
            }
            operand = word
            break
        }

        if executesText {
            guard let operand else { return InlineShell(hold: unreadableInlineShell) }
            if operand.expands || operand.substitutes || operand.text.contains("{}") {
                return InlineShell(hold: unreadableInlineShell)
            }
            return InlineShell(hold: nestedHold(operand.text, state: state))
        }
        // A script file is not a line of shell: the publishing words still apply.
        if operand != nil, !readsInput { return nil }
        if let body = input.heredocBody {
            return InlineShell(hold: nestedHold(body, state: state))
        }
        if let here = input.redirects.last(where: { $0.kind == .herestring }), let target = here.target {
            if target.expands || target.substitutes {
                return InlineShell(hold: unreadableInlineShell)
            }
            return InlineShell(hold: nestedHold(target.text, state: state))
        }
        return InlineShell(hold: "ejecuta un shell que lee comandos de la entrada")
    }

    /// Judges a nested line of shell as if it stood where this one does, links
    /// included. Its hold is inherited verbatim; only a depth limit stops it.
    private static func nestedHold(_ text: String, state: RuleState) -> String? {
        if state.depth >= inlineShellDepthLimit { return "demasiados shells en línea anidados" }
        let context = RuleContext(cwd: state.dirKnown ? state.dir : "", paths: state.context.paths)
        return assess(text, context: context, depth: state.depth + 1, links: state.madeLinks).effectiveHold
    }

    /// `kill $(pgrep ClaudeMenuBarBuddy)` and `kill 1234` look alike; only the
    /// first names the buddy (spec 5.3 point 13).
    private static func namesTheBuddy(_ word: ShellWord) -> Bool {
        let text = word.text.lowercased()
        return text.contains("claudemenubarbuddy")
            || text.contains("claude-menubar-buddy")
            || text.contains("buddy-rule")
    }
}
