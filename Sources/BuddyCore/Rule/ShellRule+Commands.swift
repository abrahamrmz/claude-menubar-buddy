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
}
