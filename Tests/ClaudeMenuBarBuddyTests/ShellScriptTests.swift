import Testing
import BuddyCore

@Suite struct ShellScriptTests {
    private func heads(_ s: String) -> [String] {
        ShellScript.parse(s).commands.compactMap { $0.words.first?.text }
    }

    @Test func plainCommandKeepsItsWords() {
        let c = ShellScript.parse("grep -n foo a.txt").commands
        #expect(c.count == 1)
        #expect(c[0].words.map(\.text) == ["grep", "-n", "foo", "a.txt"])
    }

    @Test func operatorsSplitCommands() {
        #expect(heads("cd /x && sed -n 1,5p f; tail -3 g | wc -l") == ["cd", "sed", "tail", "wc"])
        #expect(heads("a | b |& c && d || e & f") == ["a", "b", "c", "d", "e", "f"])
    }

    @Test func quotesKeepOperatorsAsText() {
        let c = ShellScript.parse(#"echo 'a; rm -rf /' "b && c""#).commands
        #expect(c.count == 1)
        #expect(c[0].words.map(\.text) == ["echo", "a; rm -rf /", "b && c"])
        #expect(c[0].words[1].quoted)
    }

    @Test func escapedSemicolonIsText() {
        #expect(ShellScript.parse("echo a\\;b").commands.map { $0.words.map(\.text) } == [["echo", "a;b"]])
    }

    @Test func substitutionsRunBeforeTheirCommand() {
        #expect(heads("cat $(python3 -c 'print(1)')") == ["python3", "cat"])
        #expect(ShellScript.parse("cat $(ls)").commands[1].words[1].substitutes)
        #expect(heads("echo `id`") == ["id", "echo"])
        #expect(heads("diff <(sort a) <(sort b)") == ["sort", "sort", "diff"])
        #expect(heads(#"echo "x $(whoami) y""#) == ["whoami", "echo"])
    }

    @Test func arithmeticIsNotACommand() {
        let s = ShellScript.parse("echo $((1+2))")
        #expect(s.commands.count == 1)
        #expect(s.commands[0].words[1].expands)
    }

    @Test func controlKeywordsAreStripped() {
        #expect(heads("for f in a b; do grep x $f; done") == ["grep"])
        #expect(heads("if test -f x; then cat x; else echo no; fi") == ["test", "cat", "echo"])
        #expect(heads("! grep x f") == ["grep"])
        #expect(heads("[[ -f x ]] && cat x") == ["[[", "cat"])
    }

    @Test func redirectOnALoopIsKept() {
        let s = ShellScript.parse("while read l; do echo $l; done < in.txt")
        #expect(heads("while read l; do echo $l; done < in.txt") == ["read", "echo"])
        let last = s.commands.last!
        #expect(last.words.isEmpty)
        #expect(last.redirects == [ShellRedirect(kind: .read, target: ShellWord(text: "in.txt", expands: false, substitutes: false, quoted: false))])
    }

    @Test func redirectKinds() {
        let r = ShellScript.parse("echo hi > out.txt 2>&1").commands[0].redirects
        #expect(r.map(\.kind) == [.write, .duplicate])
        #expect(r[0].target?.text == "out.txt")
        #expect(ShellScript.parse("echo hi >> log.txt").commands[0].redirects.map(\.kind) == [.append])
        #expect(ShellScript.parse("ls &> all.txt").commands[0].redirects.map(\.kind) == [.write])
        #expect(ShellScript.parse(#"cat <<< "$S""#).commands[0].redirects.map(\.kind) == [.herestring])
    }

    @Test func heredocBodyIsDataNotCommands() {
        let s = ShellScript.parse("cat <<EOF > f.txt\nrm -rf /\nEOF\necho done")
        #expect(s.commands.compactMap { $0.words.first?.text } == ["cat", "echo"])
        #expect(s.commands[0].heredocBody == "rm -rf /")
        #expect(s.commands[0].redirects.contains { $0.kind == .write && $0.target?.text == "f.txt" })
        #expect(ShellScript.parse("python3 - <<'PY'\nimport os\nPY").commands[0].heredocBody == "import os")
        #expect(ShellScript.parse("cat <<-EOF\n\tx\n\tEOF").commands[0].heredocBody == "x")
    }

    @Test(arguments: ["cat <<EOF\nno end", "echo 'unterminated", #"echo "open"#, "echo $(ls", "echo `ls", "echo $((1+2)"])
    func malformedInputIsUnparseable(source: String) {
        #expect(ShellScript.parse(source).unparseable)
    }

    @Test func functionsAndCaseAreFlagged() {
        #expect(ShellScript.parse("f() { ls; }; f").definesFunction)
        #expect(ShellScript.parse("function g { ls; }").definesFunction)
        #expect(ShellScript.parse("case $x in a) ls;; esac").hasCaseStatement)
    }

    @Test func subshellDepth() {
        let c = ShellScript.parse("(cd /tmp && ls); pwd").commands
        #expect(c.map(\.subshellDepth) == [1, 1, 0])
    }

    @Test func commentsEndTheLine() {
        #expect(heads("grep -r 'a|b' . # comment ; rm x") == ["grep"])
    }

    @Test func assignmentsStayAsWords() {
        #expect(ShellScript.parse("FOO=1 BAR=2 cmd x").commands[0].words.map(\.text) == ["FOO=1", "BAR=2", "cmd", "x"])
    }

    @Test func expansionFlags() {
        #expect(ShellScript.parse("echo ${HOME}/x").commands[0].words[1].expands)
        #expect(ShellScript.parse("ls *.txt").commands[0].words[1].expands)
        #expect(!ShellScript.parse("ls '*.txt'").commands[0].words[1].expands)
    }

    @Test func findExecTerminatorIsAQuotedWord() {
        let w = ShellScript.parse("find . -exec rm {} \\;").commands[0].words
        #expect(w.map(\.text) == ["find", ".", "-exec", "rm", "{}", ";"])
        #expect(w.last!.quoted)
    }
}
