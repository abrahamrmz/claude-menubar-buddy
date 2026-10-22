import Foundation

// The tools that read like filters but can write or execute through their
// own arguments. A handler looks at what the arguments actually say; the
// generic write and sensitive-path reviews still run on top of its verdict.

extension ShellRule {
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
        var index = 0
        while index < arguments.count {
            switch arguments[index].text {
            case "-delete":
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
                    var nestedState = state
                    worst = worse(worst, evaluate(CommandInput(words: nested, redirects: [],
                                                               subshellDepth: 0),
                                                  state: &nestedState))!
                }
                index = cursor + 1
            case "-fprint", "-fprint0", "-fprintf", "-fls":
                worst = worse(worst, Assessment(.desconocido, "la regla no reconoce: find"))!
                index += 1
            default:
                index += 1
            }
        }
        return worst
    }

    // MARK: - git

    static func assessGit(_ arguments: [ShellWord], state: RuleState,
                          targets: inout [WriteTarget]) -> Assessment {
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
                return Assessment(.rutaProtegida, "git -c puede ejecutar código")
            }
            if ["--git-dir", "--work-tree", "--exec-path", "--namespace"].contains(text)
                || ["--git-dir=", "--work-tree=", "--exec-path=", "--namespace="].contains(where: { text.hasPrefix($0) }) {
                return Assessment(.desconocido, "la regla no reconoce: git")
            }
            if ["--no-pager", "--paginate", "-p", "--bare", "--literal-pathspecs", "--no-optional-locks"].contains(text) {
                index += 1
                continue
            }
            if text.hasPrefix("-") {
                return Assessment(.desconocido, "la regla no reconoce: git")
            }
            subcommand = text
            subArguments = Array(arguments[(index + 1)...])
            break
        }

        guard let subcommand else {
            return Assessment(.desconocido, "la regla no reconoce: git")
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

        return assessGitSubcommand(subcommand, arguments: subArguments, state: localState)
    }

    private static let gitReadSubcommands: Set<String> = [
        "status", "log", "diff", "show", "blame", "grep", "rev-parse", "ls-files", "ls-tree", "ls-remote",
        "describe", "shortlog", "fetch", "reflog", "cat-file", "merge-base", "rev-list", "name-rev",
        "check-ignore", "check-attr", "count-objects", "help", "version", "whatchanged", "show-ref",
        "for-each-ref", "var",
    ]

    private static let gitLocalChangeSubcommands: Set<String> = [
        "add", "commit", "switch", "merge", "pull", "rebase", "cherry-pick", "revert", "tag", "mv", "rm",
        "am", "apply", "init", "clone", "notes", "bisect", "sparse-checkout",
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
            if second == "clone" { return Assessment(.cambioLocal, "cambio local") }
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
        var index = 0
        var host: String?
        var remoteWords: [String] = []

        while index < arguments.count {
            let text = arguments[index].text
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
            remoteWords.append(text)
            index += 1
        }

        guard host != nil, !remoteWords.isEmpty else {
            return Assessment(.sale, "ssh interactivo")
        }

        let script = ShellScript.parse(remoteWords.joined(separator: " "))
        if script.unparseable || script.hasCaseStatement || script.definesFunction {
            return Assessment(.sale, "ssh que no solo lee")
        }

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
                    return Assessment(.sensible, "toca un archivo sensible: \(canonical)")
                }
            }
        }

        for simple in script.commands where !remoteSimpleIsRead(simple, state: state) {
            return Assessment(.sale, "ssh que no solo lee")
        }
        return Assessment(.lectura, "ssh que solo lee")
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
}
