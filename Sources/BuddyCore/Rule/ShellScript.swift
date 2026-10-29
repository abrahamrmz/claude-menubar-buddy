import Foundation

/// One word of a simple command, with the three facts the rule needs about
/// it: whether it can expand into something else, whether it runs a command
/// of its own, and whether any part of it came from quotes or an escape.
public struct ShellWord: Equatable {
    /// Quotes and escapes removed; `$VAR`, `${…}`, `$(…)`, `` `…` `` kept as
    /// written so the rule can report what it could not resolve.
    public var text: String
    /// Unquoted (or double-quoted) `$`-expansion, or an unquoted glob.
    public var expands: Bool
    /// Contains `$(…)`, `` `…` ``, `<(…)` or `>(…)`.
    public var substitutes: Bool
    /// Some part was quoted or backslash-escaped.
    public var quoted: Bool

    public init(text: String, expands: Bool, substitutes: Bool, quoted: Bool) {
        self.text = text
        self.expands = expands
        self.substitutes = substitutes
        self.quoted = quoted
    }
}

public enum RedirectKind: Equatable {
    case write, append, read, duplicate, heredoc, herestring
}

public struct ShellRedirect: Equatable {
    public var kind: RedirectKind
    /// The destination word. `nil` only for a heredoc, whose delimiter is
    /// consumed rather than kept as a destination.
    public var target: ShellWord?

    public init(kind: RedirectKind, target: ShellWord?) {
        self.kind = kind
        self.target = target
    }
}

public struct SimpleCommand: Equatable {
    public var words: [ShellWord]
    public var redirects: [ShellRedirect]
    public var subshellDepth: Int
    /// The heredoc body, when this command carried one. Data, never commands.
    public var heredocBody: String?
}

public struct ShellScript: Equatable {
    /// Every simple command, flattened, in execution order. A substitution's
    /// commands come before the command that holds the substitution.
    public var commands: [SimpleCommand]
    /// The source could not be read to the end: an open quote, an open
    /// substitution, an unfinished heredoc. Never treat this as "plain".
    public var unparseable: Bool
    public var definesFunction: Bool
    public var hasCaseStatement: Bool

    public static func parse(_ source: String) -> ShellScript {
        var parser = Parser(source: source)
        return parser.run()
    }
}

// A character scanner, not a grammar. It only has to be right about the
// things the rule decides on: where a command starts and ends, what it
// writes to, and what it refuses to understand.
private struct Parser {
    private let src: [Character]
    private var i = 0

    private var commands: [SimpleCommand] = []
    private var words: [ShellWord] = []
    private var redirects: [ShellRedirect] = []
    private var word = WordAccumulator()

    private var pending: [SimpleCommand] = []
    private var heredocs: [(delimiter: String, stripTabs: Bool)] = []
    private var pendingHeredoc: Bool?
    private var pendingTarget: Int?
    /// Which `>&` / `<&` opened the pending redirect, when one did. Bash
    /// treats `>&file` as a write to file, not a descriptor duplication.
    private var pendingDuplicateFrom: Character?

    private var unparseable = false
    private var definesFunction = false
    private var hasCaseStatement = false
    private var subshellDepth = 0

    private struct WordAccumulator {
        var text = ""
        var expands = false
        var substitutes = false
        var quoted = false
        var started = false
    }

    init(source: String) {
        src = Array(source)
    }

    private func peek(_ offset: Int) -> Character? {
        let k = i + offset
        return k >= 0 && k < src.count ? src[k] : nil
    }

    mutating func run() -> ShellScript {
        while i < src.count {
            let c = src[i]
            switch c {
            case " ", "\t":
                flushWord()
                i += 1
            case "\r":
                i += 1
            case "\n":
                i += 1
                let completed = closeCommand()
                if !heredocs.isEmpty { readHeredocBodies(into: completed) }
            case "#":
                if !word.started {
                    while i < src.count && src[i] != "\n" { i += 1 }
                } else {
                    append(c)
                    i += 1
                }
            case "'":
                parseSingleQuote()
            case "\"":
                parseDoubleQuote()
            case "\\":
                parseEscape()
            case "$":
                parseDollar()
            case "`":
                parseBacktick()
            case "<", ">":
                if peek(1) == "(" {
                    flushWord()
                    parseSubstitution(openLength: 2)
                } else {
                    parseRedirect(at: i)
                }
            case "&":
                parseAmpersand()
            case ";":
                flushWord()
                _ = closeCommand()
                if peek(1) == ";" {
                    hasCaseStatement = true
                    i += 2
                } else {
                    i += 1
                }
            case "|":
                flushWord()
                _ = closeCommand()
                i += peek(1) == "&" ? 2 : 1
            case "(":
                parseOpenParen()
            case ")":
                flushWord()
                _ = closeCommand()
                if subshellDepth > 0 { subshellDepth -= 1 }
                i += 1
            default:
                if c.isNumber, !word.started, let redirectIndex = redirectIndexAfterDigits() {
                    flushWord()
                    i = redirectIndex
                    parseRedirect(at: redirectIndex)
                } else {
                    // `[[` is bash's keyword, not a glob: marking it as an
                    // expansion would turn every `[[ -f x ]]` into a card.
                    if c == "*" || c == "?" { word.expands = true }
                    if c == "[", peek(1) != "[", word.text.last != "[" { word.expands = true }
                    append(c)
                    i += 1
                }
            }
        }
        flushWord()
        _ = closeCommand()
        if !heredocs.isEmpty { unparseable = true }
        return ShellScript(commands: commands,
                           unparseable: unparseable,
                           definesFunction: definesFunction,
                           hasCaseStatement: hasCaseStatement)
    }

    // MARK: - Words

    private mutating func append(_ c: Character) {
        word.text.append(c)
        word.started = true
    }

    private mutating func startWord() {
        word.started = true
    }

    private mutating func flushWord() {
        guard word.started else { return }
        let w = ShellWord(text: word.text,
                          expands: word.expands,
                          substitutes: word.substitutes,
                          quoted: word.quoted)
        if let stripTabs = pendingHeredoc {
            pendingHeredoc = nil
            pendingDuplicateFrom = nil
            heredocs.append((w.text, stripTabs))
        } else if let index = pendingTarget {
            pendingTarget = nil
            // `>&word` and `<&word` duplicate a descriptor only when the word
            // is a descriptor: digits or `-`. Anything else is a file, so the
            // rule has to see it as a write (or read) and look at the path.
            if redirects[index].kind == .duplicate, let origin = pendingDuplicateFrom {
                let isDescriptor = !w.text.isEmpty && (w.text.allSatisfy(\.isNumber) || w.text == "-")
                if !isDescriptor {
                    redirects[index].kind = origin == ">" ? .write : .read
                }
            }
            pendingDuplicateFrom = nil
            redirects[index].target = w
        } else {
            words.append(w)
        }
        word = WordAccumulator()
    }

    private mutating func parseSingleQuote() {
        startWord()
        word.quoted = true
        var k = i + 1
        while k < src.count && src[k] != "'" { k += 1 }
        guard k < src.count else {
            unparseable = true
            word.text += String(src[(i + 1)...])
            i = src.count
            return
        }
        word.text += String(src[(i + 1)..<k])
        i = k + 1
    }

    private mutating func parseDoubleQuote() {
        startWord()
        word.quoted = true
        i += 1
        while i < src.count {
            let c = src[i]
            if c == "\"" {
                i += 1
                return
            }
            if c == "\\" {
                guard let next = peek(1) else {
                    append(c)
                    i += 1
                    continue
                }
                if "\"$`\\\n".contains(next) {
                    if next != "\n" { append(next) }
                    i += 2
                } else {
                    append(c)
                    i += 1
                }
                continue
            }
            if c == "$" {
                parseDollar()
                continue
            }
            if c == "`" {
                parseBacktick()
                continue
            }
            append(c)
            i += 1
        }
        unparseable = true
    }

    private mutating func parseEscape() {
        startWord()
        word.quoted = true
        guard let next = peek(1) else {
            append("\\")
            i += 1
            return
        }
        append(next)
        i += 2
    }

    // MARK: - Expansions and substitutions

    private mutating func parseDollar() {
        startWord()
        guard let next = peek(1) else {
            append("$")
            i += 1
            return
        }
        if next == "(" {
            if peek(2) == "(" {
                parseArithmetic()
            } else {
                parseSubstitution(openLength: 2)
            }
            return
        }
        if next == "{" {
            var k = i + 2
            while k < src.count && src[k] != "}" { k += 1 }
            word.expands = true
            guard k < src.count else {
                unparseable = true
                word.text += String(src[i...])
                i = src.count
                return
            }
            word.text += String(src[i...k])
            i = k + 1
            return
        }
        if next.isLetter || next.isNumber || "$_@?*#!-".contains(next) {
            word.expands = true
            var k = i + 1
            if "$_@?*#!-".contains(next) {
                k += 1
            } else {
                while k < src.count,
                      src[k].isLetter || src[k].isNumber || src[k] == "_" {
                    k += 1
                }
            }
            word.text += String(src[i..<k])
            i = k
            return
        }
        append("$")
        i += 1
    }

    private mutating func parseArithmetic() {
        startWord()
        word.expands = true
        var depth = 0
        var k = i + 3
        while k < src.count {
            let c = src[k]
            if c == "(" {
                depth += 1
                k += 1
            } else if c == ")" {
                if depth > 0 {
                    depth -= 1
                    k += 1
                } else if k + 1 < src.count && src[k + 1] == ")" {
                    word.text += String(src[i..<(k + 2)])
                    i = k + 2
                    return
                } else {
                    k += 1
                }
            } else if c == "'" {
                var m = k + 1
                while m < src.count && src[m] != "'" { m += 1 }
                if m >= src.count { break }
                k = m + 1
            } else if c == "\"" {
                var m = k + 1
                while m < src.count && src[m] != "\"" {
                    m += src[m] == "\\" ? 2 : 1
                }
                if m >= src.count { break }
                k = m + 1
            } else {
                k += 1
            }
        }
        unparseable = true
        word.text += String(src[i...])
        i = src.count
    }

    /// `$(…)`, `<(…)` or `>(…)`: find the matching close, parse the inside on
    /// its own, and splice its commands in ahead of whatever contains it.
    private mutating func parseSubstitution(openLength: Int) {
        startWord()
        let innerStart = i + openLength
        guard let close = findParenClose(from: innerStart) else {
            unparseable = true
            word.substitutes = true
            word.text += String(src[i...])
            i = src.count
            return
        }
        let inner = String(src[innerStart..<close])
        inherit(Parsed(ShellScript.parse(inner)))
        word.substitutes = true
        word.text += String(src[i...close])
        i = close + 1
    }

    private mutating func parseBacktick() {
        startWord()
        guard let close = findBacktickClose(from: i + 1) else {
            unparseable = true
            word.substitutes = true
            word.text += String(src[i...])
            i = src.count
            return
        }
        let inner = String(src[(i + 1)..<close])
        inherit(Parsed(ShellScript.parse(inner)))
        word.substitutes = true
        word.text += String(src[i...close])
        i = close + 1
    }

    private struct Parsed {
        let commands: [SimpleCommand]
        let unparseable: Bool
        let definesFunction: Bool
        let hasCaseStatement: Bool

        init(_ script: ShellScript) {
            commands = script.commands
            unparseable = script.unparseable
            definesFunction = script.definesFunction
            hasCaseStatement = script.hasCaseStatement
        }
    }

    private mutating func inherit(_ nested: Parsed) {
        pending.append(contentsOf: nested.commands)
        if nested.unparseable { unparseable = true }
        if nested.definesFunction { definesFunction = true }
        if nested.hasCaseStatement { hasCaseStatement = true }
    }

    private func findParenClose(from start: Int) -> Int? {
        var depth = 0
        var k = start
        while k < src.count {
            let c = src[k]
            if c == "\\" {
                k += 2
            } else if c == "'" {
                var m = k + 1
                while m < src.count && src[m] != "'" { m += 1 }
                if m >= src.count { return nil }
                k = m + 1
            } else if c == "\"" {
                var m = k + 1
                while m < src.count {
                    if src[m] == "\\" {
                        m += 2
                    } else if src[m] == "\"" {
                        break
                    } else {
                        m += 1
                    }
                }
                if m >= src.count { return nil }
                k = m + 1
            } else if c == "(" {
                depth += 1
                k += 1
            } else if c == ")" {
                if depth == 0 { return k }
                depth -= 1
                k += 1
            } else {
                k += 1
            }
        }
        return nil
    }

    private func findBacktickClose(from start: Int) -> Int? {
        var k = start
        while k < src.count {
            if src[k] == "\\" {
                k += 2
            } else if src[k] == "`" {
                return k
            } else {
                k += 1
            }
        }
        return nil
    }

    // MARK: - Redirects

    private func redirectIndexAfterDigits() -> Int? {
        var k = i
        while k < src.count && src[k].isNumber { k += 1 }
        guard k < src.count, src[k] == "<" || src[k] == ">" else { return nil }
        return k
    }

    private mutating func parseRedirect(at index: Int) {
        flushWord()
        var k = index
        var kind: RedirectKind
        var stripTabs = false
        let c = src[k]
        if c == ">" {
            if k + 1 < src.count && src[k + 1] == ">" {
                kind = .append
                k += 2
            } else if k + 1 < src.count && src[k + 1] == "|" {
                kind = .write
                k += 2
            } else if k + 1 < src.count && src[k + 1] == "&" {
                kind = .duplicate
                k += 2
            } else {
                kind = .write
                k += 1
            }
        } else {
            if k + 1 < src.count && src[k + 1] == "<" {
                if k + 2 < src.count && src[k + 2] == "<" {
                    kind = .herestring
                    k += 3
                } else if k + 2 < src.count && src[k + 2] == "-" {
                    kind = .heredoc
                    stripTabs = true
                    k += 3
                } else {
                    kind = .heredoc
                    k += 2
                }
            } else if k + 1 < src.count && src[k + 1] == ">" {
                kind = .read
                k += 2
            } else if k + 1 < src.count && src[k + 1] == "&" {
                kind = .duplicate
                k += 2
            } else {
                kind = .read
                k += 1
            }
        }
        redirects.append(ShellRedirect(kind: kind, target: nil))
        i = k
        if kind == .heredoc {
            pendingHeredoc = stripTabs
            pendingDuplicateFrom = nil
        } else {
            pendingTarget = redirects.count - 1
            pendingDuplicateFrom = kind == .duplicate ? c : nil
        }
    }

    private mutating func parseAmpersand() {
        if peek(1) == ">" {
            flushWord()
            let kind: RedirectKind = peek(2) == ">" ? .append : .write
            redirects.append(ShellRedirect(kind: kind, target: nil))
            pendingTarget = redirects.count - 1
            pendingDuplicateFrom = nil
            i += peek(2) == ">" ? 3 : 2
            return
        }
        flushWord()
        _ = closeCommand()
        i += peek(1) == "&" ? 2 : 1
    }

    // MARK: - Parentheses

    private mutating func parseOpenParen() {
        if word.started && peek(1) == ")" {
            definesFunction = true
            word = WordAccumulator()
            i += 2
            return
        }
        flushWord()
        _ = closeCommand()
        subshellDepth += 1
        i += 1
    }

    // MARK: - Heredocs

    private mutating func readHeredocBodies(into completedIndex: Int?) {
        let pendingBodies = heredocs
        heredocs = []
        for heredoc in pendingBodies {
            let (body, next, closed) = readHeredoc(from: i,
                                                   delimiter: heredoc.delimiter,
                                                   stripTabs: heredoc.stripTabs)
            if !closed {
                unparseable = true
                i = src.count
                return
            }
            if let index = completedIndex {
                commands[index].heredocBody = body
            }
            i = next
        }
    }

    private func readHeredoc(from start: Int, delimiter: String,
                             stripTabs: Bool) -> (String, Int, Bool) {
        var k = start
        var lines: [String] = []
        while k <= src.count {
            var end = k
            while end < src.count && src[end] != "\n" { end += 1 }
            var line = String(src[k..<end])
            if stripTabs { line = String(line.drop(while: { $0 == "\t" })) }
            let next = end < src.count ? end + 1 : end
            if line == delimiter { return (lines.joined(separator: "\n"), next, true) }
            lines.append(line)
            if end >= src.count { break }
            k = next
        }
        return (lines.joined(separator: "\n"), src.count, false)
    }

    // MARK: - Command boundaries

    private static let controlKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}",
    ]

    private mutating func closeCommand() -> Int? {
        flushWord()
        // A redirect that never got its target (`> ;`, `cat << |`) is not a
        // command the rule can reason about. Clear the pending slot here, so
        // it can never be handed the next command's word and index into a
        // redirects array that no longer exists.
        if pendingTarget != nil || pendingHeredoc != nil {
            unparseable = true
            pendingTarget = nil
            pendingHeredoc = nil
            pendingDuplicateFrom = nil
        }
        var command = SimpleCommand(words: words, redirects: redirects,
                                    subshellDepth: subshellDepth, heredocBody: nil)
        words = []
        redirects = []

        while let first = command.words.first,
              !first.quoted,
              Self.controlKeywords.contains(first.text) {
            command.words.removeFirst()
        }

        let head = command.words.first.flatMap { $0.quoted ? nil : $0.text }
        if head == "for" || head == "select" {
            commands.append(contentsOf: pending)
            pending = []
            return nil
        }
        if head == "case" { hasCaseStatement = true }
        if head == "function" { definesFunction = true }

        commands.append(contentsOf: pending)
        pending = []
        if command.words.isEmpty && command.redirects.isEmpty { return nil }
        commands.append(command)
        return commands.count - 1
    }
}
