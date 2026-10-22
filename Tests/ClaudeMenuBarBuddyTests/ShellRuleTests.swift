import Testing
import BuddyCore

let ruleContext = RuleContext(
    cwd: "/Users/u/repo",
    paths: PathPolicy(home: "/Users/u",
                      pathDirs: ["/usr/bin", "/bin", "/opt/homebrew/bin"],
                      tempDirs: ["/tmp", "/private/tmp"],
                      probe: StubProbe(dirs: ["/", "/Users/u/repo", "/Users/u/Documents"],
                                       files: ["/Users/u/Documents/a.txt", "/Users/u/repo/b.txt"],
                                       gitRoots: ["/Users/u/repo"])))

func category(_ command: String) -> RuleCategory {
    ShellRule.assess(command, context: ruleContext).category
}

@Suite struct ShellRuleTests {
    @Test(arguments: [
        "grep -rn foo src", "cd /Users/u/repo && sed -n 1,40p a.swift; tail -5 b.txt | wc -l", "ls -la",
        "cat a.txt | head -20", "echo hola", "jq .x data.json", "find . -name '*.swift'",
        "for f in a b; do grep x $f; done", "D=/tmp/x; grep foo $D/log", "/usr/bin/grep x f",
        "echo hi > /dev/null 2>&1", "[[ -f x ]] && cat x", "pwd; which swift", "sort data.txt | uniq -c",
    ])
    func reads(command: String) { #expect(category(command) == .lectura, "\(command)") }

    @Test(arguments: [
        "mkdir -p build/out", "cp a.txt c.txt", "mv x y", "echo x >> notes.md", "cat a.txt > /tmp/copia.txt",
        "touch nuevo.txt", "tee out.txt < a.txt", "echo x > b.txt",   // b.txt exists but is inside git
    ])
    func localChanges(command: String) { #expect(category(command) == .cambioLocal, "\(command)") }

    @Test(arguments: [
        "python3 -c 'print(1)'", "python3 script.py", "venv/bin/python manage.py test", "./venv/bin/python -m pytest",
        "pytest -q", "bash -c 'ls'", "node build.js", "swift build", "npm install", "pnpm install", "uvx ruff check",
        "brew install jq", "make", "osascript -e 'x'", "open https://x", "launchctl list", "sqlite3 db.sqlite3 'select 1'",
        "sudo ls", "eval ls", "source .venv/bin/activate", ". ./env.sh", "./script.sh", "~/bin/tool",
        "/opt/homebrew/bin/python3 x.py", "/Users/u/repo/tools/grep x", "PATH=/tmp/evil ls",
        "DYLD_INSERT_LIBRARIES=/tmp/x.dylib ls", "export PATH=/tmp:$PATH", "GIT_PAGER=sh git log", "nohup python3 w.py",
        "timeout 5 node x.js", "env python3 x.py",
    ])
    func executes(command: String) { #expect(category(command) == .ejecuta, "\(command)") }

    @Test(arguments: ["rm -rf build", "rmdir x", "kill 123", "pkill -f celery", "truncate -s 0 a.txt", "dd if=/dev/zero of=x"])
    func irreversible(command: String) { #expect(category(command) == .irreversible, "\(command)") }

    @Test(arguments: ["curl -s https://x", "wget x", "scp a h:/tmp", "rsync -a . h:/x", "./deploy_remote.sh", "ping -c1 x", "dig x.com"])
    func leavesTheMachine(command: String) { #expect(category(command) == .sale, "\(command)") }

    @Test(arguments: [
        "echo x >> ~/.zshrc", "cp evil.plist ~/Library/LaunchAgents/x.plist", "cd ~/.ssh && echo k > authorized_keys",
        "tee .git/config < x", "cp x /opt/homebrew/bin/ls", "touch .husky/pre-commit", "chmod +x .git/hooks/pre-commit",
        "mv ~/.zshrc /tmp/zshrc.bak", "echo x >& ~/.zshrc",
    ])
    func protectedWrites(command: String) { #expect(category(command) == .rutaProtegida, "\(command)") }

    @Test(arguments: ["cat .env", "grep TOKEN .env.production", "cat ~/.aws/credentials", "cp .env /tmp/x", "cat < .env", "head --file=.env"])
    func sensitive(command: String) { #expect(category(command) == .sensible, "\(command)") }

    @Test(arguments: ["echo x > ~/Documents/a.txt", "cp b.txt ~/Documents/a.txt", "tee ~/Documents/a.txt < b.txt"])
    func unrecoverableOverwrite(command: String) { #expect(category(command) == .sobrescribe, "\(command)") }

    @Test(arguments: [
        "mytool --run", "FOO=1 ls", "$CMD arg", "$(echo ls) -la", "alias ll='ls -l'", "f() { ls; }; f",
        "echo 'sin cerrar", "case x in a) ls;; esac", "echo x > $OUT", "cd $DIR && echo x > out.txt", "sort -o out.txt in.txt",
        "uniq in.txt out.txt", "yq -i '.a=1' x.yml",
    ])
    func unknown(command: String) { #expect(category(command) == .desconocido, "\(command)") }

    @Test func worstSegmentWins() {
        #expect(category("grep x f; python3 y.py") == .ejecuta)
        #expect(category("ls && mytool") == .desconocido)
        #expect(category("mytool; rm -rf x") == .irreversible)
        #expect(category("echo a > /tmp/x && cat /tmp/x") == .cambioLocal)
    }

    @Test func reasons() {
        #expect(ShellRule.assess("python3 y.py", context: ruleContext).reason == "ejecuta código: python3")
        #expect(ShellRule.assess("echo x >> ~/.zshrc", context: ruleContext).reason == "escribe en una ruta protegida: /Users/u/.zshrc")
        #expect(ShellRule.assess("rm -rf build", context: ruleContext).reason == "no se puede deshacer: rm")
        #expect(ShellRule.assess("sudo ls", context: ruleContext).reason == "ejecuta con sudo")
        #expect(ShellRule.assess("PATH=/x ls", context: ruleContext).reason == "cambia cómo se resuelve el comando: PATH=")
        #expect(ShellRule.assess("echo 'x", context: ruleContext).reason == "no se pudo analizar el comando")
    }

    @Test func subshellCdMakesLaterRelativeWritesUnknown() {
        #expect(category("(cd /tmp); echo x > out.txt") == .desconocido)
    }

    @Test(arguments: ["echo 'x", "cat $(ls", "cat <<EOF\nx", ""])
    func malformedNeverPasses(command: String) {
        let a = ShellRule.assess(command, context: ruleContext)
        if command.isEmpty { #expect(a.category == .desconocido) } else { #expect(!a.category.passesInAutoMode) }
    }
}
