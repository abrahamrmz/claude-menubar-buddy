import Testing
import BuddyCore

/// The session hold the rule puts on `command`, or nil when a grant may cover it.
func holdOf(_ command: String, in context: RuleContext = ruleContext) -> String? {
    ShellRule.assess(command, context: context).effectiveHold
}

/// Spec 5.3, points 1 to 9: without these, one line of shell breaks the
/// promise of "everything but publishing".
@Suite struct SessionHoldTests {
    // Point 1.
    @Test func sudoAndDoas() {
        #expect(ShellRule.assess("sudo git push", context: ruleContext)
                == Assessment(.ejecuta, "ejecuta con sudo", sessionHold: "usa sudo"))
        #expect(holdOf("doas ls") == "usa doas")
        #expect(holdOf("echo x | sudo tee /etc/hosts") == "usa sudo")
        #expect(holdOf("nohup sudo ls") == "usa sudo")
        #expect(holdOf("/usr/bin/sudo git push") == "usa sudo")
        #expect(holdOf("ls | xargs sudo rm x") == "usa sudo")
    }

    // Point 2.
    @Test func assignmentsThatChangeWhatRuns() {
        #expect(ShellRule.assess("PATH=/tmp:$PATH git push", context: ruleContext)
                == Assessment(.ejecuta, "cambia cómo se resuelve el comando: PATH=",
                              sessionHold: "cambia cómo se resuelve el comando: PATH="))
        #expect(holdOf("DYLD_INSERT_LIBRARIES=/tmp/x.dylib ls") == "cambia cómo se resuelve el comando: DYLD_INSERT_LIBRARIES=")
        #expect(holdOf("LD_PRELOAD=/tmp/x.so ls") == "cambia cómo se resuelve el comando: LD_PRELOAD=")
        #expect(holdOf("GIT_SSH_COMMAND=x git fetch") == "cambia cómo se resuelve el comando: GIT_SSH_COMMAND=")
        #expect(holdOf("BASH_ENV=/tmp/x bash x.sh") == "cambia cómo se resuelve el comando: BASH_ENV=")
        #expect(holdOf("env PATH=/tmp python3 x.py") == "cambia cómo se resuelve el comando: PATH=")
        #expect(holdOf("export PATH=/tmp:$PATH") == "cambia cómo se resuelve el comando: PATH=")
        #expect(holdOf("PATH=/tmp/evil; ls") == "cambia cómo se resuelve el comando: PATH=")
        #expect(holdOf("FOO=1 python3 x.py") == nil)
    }

    // Point 3, plus `alias`: a definition decides what a later word runs.
    @Test func whatTheRuleCannotRead() {
        #expect(ShellRule.assess("", context: ruleContext)
                == Assessment(.desconocido, "la regla no reconoce: ", sessionHold: "comando vacío"))
        #expect(holdOf("   ") == "comando vacío")
        #expect(holdOf("echo 'sin cerrar") == "no se pudo analizar el comando")
        #expect(holdOf("case x in a) git push;; esac") == "no se pudo analizar el comando")
        #expect(holdOf("f() { git push; }; f") == "define funciones de shell")
        #expect(holdOf("function g { ls; }") == "define funciones de shell")
        #expect(holdOf("alias p='git push'") == "define un alias")
    }

    // Point 4.
    @Test func aCommandWordThatIsAVariable() {
        #expect(ShellRule.assess("C=\"git push\"; $C", context: ruleContext)
                == Assessment(.desconocido, "la regla no reconoce: $C", sessionHold: "no se sabe qué comando corre: $C"))
        #expect(holdOf("$(echo git) push") == "no se sabe qué comando corre: $(echo git)")
        #expect(holdOf("`echo git` push") == "no se sabe qué comando corre: `echo git`")
        #expect(holdOf("env $C") == "no se sabe qué comando corre: $C")
        #expect(holdOf("ls | xargs $C") == "no se sabe qué comando corre: $C")
    }

    // Point 5, plus a file that lands in a folder under a name the rule can't read.
    @Test func aWriteThatCannotBeResolved() {
        #expect(ShellRule.assess("F=~/.zshrc; echo x >> $F", context: ruleContext)
                == Assessment(.desconocido, "no se puede saber dónde escribe", sessionHold: "no se sabe dónde escribe: $F"))
        #expect(holdOf("cd $DIR && echo x > out.txt") == "no se sabe dónde escribe: out.txt")
        #expect(holdOf("tee $(cat dest) < a.txt") == "no se sabe dónde escribe: $(cat dest)")
        #expect(holdOf("sed -i '' 's/a/b/' $F") == "no se sabe dónde escribe: $F")
        #expect(holdOf("ln -s \"$HOME\" h") == "no se sabe a dónde apunta el enlace: $HOME")
        #expect(holdOf("cp \"$F\" ~/Documents/") == "no se sabe dónde escribe: $F")
        #expect(holdOf("cp -t ~ \"$F\"") == "no se sabe dónde escribe: $F")
        #expect(holdOf("mv \"$F\" /tmp/x") == "no se sabe dónde escribe: $F")
        // Readable names keep passing.
        #expect(holdOf("cp \"$F\" out.txt") == nil)
        #expect(holdOf("echo x > out.txt") == nil)
        #expect(holdOf("cp a.txt ~/Documents/") == nil)
    }

    // Point 6.
    @Test func writersTheRuleDoesNotFollow() {
        #expect(ShellRule.assess("sort -o out.txt in.txt", context: ruleContext)
                == Assessment(.desconocido, "la regla no reconoce: sort",
                              sessionHold: "escribe un archivo que la regla no revisa: sort"))
        #expect(holdOf("tree -o out.txt") == "escribe un archivo que la regla no revisa: tree")
        #expect(holdOf("yq -i '.a=1' x.yml") == "escribe un archivo que la regla no revisa: yq")
        #expect(holdOf("uniq in.txt out.txt") == "escribe un archivo que la regla no revisa: uniq")
        #expect(holdOf("find . -fprint out") == "escribe un archivo que la regla no revisa: find")
        #expect(holdOf("sort -u a.txt") == nil)
    }

    // Point 7: the category stays `irreversible`; only the hold is new.
    @Test(arguments: [
        ("rm ~/.zshrc", "borra una ruta protegida: /Users/u/.zshrc"),
        ("rm -rf .git", "borra una ruta protegida: /Users/u/repo/.git"),
        ("rmdir ~/.ssh", "borra una ruta protegida: /Users/u/.ssh"),
        ("unlink ~/.gitconfig", "borra una ruta protegida: /Users/u/.gitconfig"),
        ("shred -u ~/.ssh/id_ed25519", "borra una ruta protegida: /Users/u/.ssh/id_ed25519"),
        ("truncate -s 0 ~/.zshrc", "borra una ruta protegida: /Users/u/.zshrc"),
        ("dd if=/dev/zero of=~/.zshrc", "borra una ruta protegida: /Users/u/.zshrc"),
        ("rm -rf ~/.config", "borra una carpeta que guarda rutas protegidas: /Users/u/.config"),
        ("rm -rf ~", "borra una carpeta que guarda rutas protegidas: /Users/u"),
        ("rm -rf -- ~", "borra una carpeta que guarda rutas protegidas: /Users/u"),
        ("rm -rf /", "borra una carpeta que guarda rutas protegidas: /"),
        ("rm -rf ..", "borra una carpeta que guarda rutas protegidas: /Users/u"),
        ("rm -rf ~/Library", "borra una carpeta que guarda rutas protegidas: /Users/u/Library"),
        ("rm -rf \"$D\"", "no se sabe qué borra: $D"),
        ("rm -rf $(cat lista)", "no se sabe qué borra: $(cat lista)"),
        ("rm -rf ~root", "no se sabe qué borra: ~root"),
        ("cd $D && rm -rf build", "no se sabe qué borra: build"),
        ("rm -rf ~/.ssh/*", "borra con un comodín peligroso: ~/.ssh/*"),
        ("rm -rf ~/*", "borra con un comodín peligroso: ~/*"),
        ("rm -rf /*", "borra con un comodín peligroso: /*"),
        ("rm .*", "borra con un comodín peligroso: .*"),
        ("rm -rf */.git", "borra con un comodín peligroso: */.git"),
        ("find ~ -name '*.bak' -delete", "borra una carpeta que guarda rutas protegidas: /Users/u"),
        ("find ~/.ssh -exec rm {} \\;", "borra una ruta protegida: /Users/u/.ssh"),
        ("ls | xargs rm -rf ~", "borra una carpeta que guarda rutas protegidas: /Users/u"),
        ("ln -s ~ h && rm -rf h/", "borra una carpeta que guarda rutas protegidas: /Users/u/repo/h → /Users/u"),
    ])
    func deletingWhatMustStay(command: String, why: String) {
        #expect(holdOf(command) == why, "\(command)")
        #expect(ShellRule.assess(command, context: ruleContext).category == .irreversible, "\(command)")
    }

    @Test(arguments: [
        "rm -rf build", "rm -rf build/*", "rm -rf proyecto-viejo", "rm -f *.log", "rm -rf ../otro", "rm -rf /tmp/x",
        "rmdir out", "truncate -s 0 a.txt", "rm -rf ~/proyectos/viejo", "find . -name '*.pyc' -delete",
        "find . -name '*.pyc' -exec rm {} \\;", "ls | xargs rm", "dd if=/dev/zero of=x",
    ])
    func deletingOrdinaryThingsPasses(command: String) { #expect(holdOf(command) == nil, "\(command)") }

    @Test func pinnedProtectedContainer() {
        let p = ruleContext.paths
        #expect(p.pinnedProtectedContainer("/") == "/")
        #expect(p.pinnedProtectedContainer("/Users") == "/Users")
        #expect(p.pinnedProtectedContainer("/Users/u") == "/Users/u")
        #expect(p.pinnedProtectedContainer("/Users/u/.config") == "/Users/u/.config")
        #expect(p.pinnedProtectedContainer("/Users/u/Library") == "/Users/u/Library")
        #expect(p.pinnedProtectedContainer("/opt/homebrew") == "/opt/homebrew")   // holds a folder of the PATH
        #expect(p.pinnedProtectedContainer("/USERS/U/.CONFIG") == "/USERS/U/.CONFIG")
        // Protected by name only: that is protectedSpelling's job, not this one.
        #expect(p.pinnedProtectedContainer("/Users/u/.ssh") == nil)
        #expect(p.pinnedProtectedContainer("/Users/u/repo") == nil)
        #expect(p.pinnedProtectedContainer("/Users/u/proyectos") == nil)
        let linked = PathPolicy(home: "/Users/u", pathDirs: [], tempDirs: [],
                                probe: StubProbe(dirs: ["/", "/Users/u", "/Users/u/repo"],
                                                 links: ["/Users/u/repo/h": "/Users/u"]))
        #expect(linked.pinnedProtectedContainer("/Users/u/repo/h") == "/Users/u")
    }

    // Point 8.
    @Test func gitThatLeavesOrIsUnknown() {
        #expect(ShellRule.assess("git push --receive-pack=x origin", context: ruleContext)
                == Assessment(.ejecuta, "ejecuta código a través de una opción: --receive-pack",
                              sessionHold: "sale de tu máquina: git push"))
        #expect(holdOf("git push") == "sale de tu máquina: git push")
        #expect(holdOf("git -C /tmp/x push") == "sale de tu máquina: git push")
        #expect(holdOf("git send-email x.patch") == "la regla no reconoce: git send-email")
        #expect(holdOf("git lfs push origin") == "la regla no reconoce: git lfs")
        #expect(holdOf("git subtree push --prefix=x origin y") == "la regla no reconoce: git subtree")
        #expect(holdOf("git --git-dir=/x log") == "la regla no reconoce: git")
        #expect(holdOf("ls | xargs git") == "la regla no reconoce: git")
        #expect(holdOf("git status") == nil)
        #expect(holdOf("git commit -m \"deploy fix\"") == nil)
        #expect(holdOf("git reset --hard") == nil)
        #expect(holdOf("git fetch origin") == nil)
    }

    // Point 9.
    @Test func sshThatDoesMoreThanRead() {
        #expect(holdOf("ssh h 'cat .env; sudo reboot'") == "ssh que no solo lee")
        #expect(holdOf("ssh h") == "ssh interactivo")
        #expect(holdOf("ssh -F ./cfg h ls") == "ssh que no solo lee")
        #expect(holdOf("ssh -oProxyCommand=evil h ls") == "ssh que no solo lee")
        #expect(ShellRule.assess("ssh h \"echo $(cat .env)\"", context: ruleContext)
                == Assessment(.sensible, "toca un archivo sensible: /Users/u/repo/.env",
                              sessionHold: "ssh con una expansión local"))
        #expect(holdOf("ssh h \"tail -n 5 $LOG\"") == "ssh con una expansión local")
        #expect(holdOf("ssh h 'tail -n 5 $LOG'") == nil)
        #expect(holdOf("ssh h 'cat /srv/.env'") == nil)
    }

    @Test(arguments: ["rm -rf build", "python3 a.py", "cat .env"])
    func pushNextToAnythingStaysHeld(x: String) {
        #expect(holdOf("\(x); git push") == "sale de tu máquina: git push", "\(x)")
        #expect(holdOf("git push; \(x)") == "sale de tu máquina: git push", "\(x)")
    }

    /// Spec 5.3, "pasan con concesión". Nothing here may gain a hold.
    @Test(arguments: [
        "rm -rf build", "rm -rf build/*", "rm -rf proyecto-viejo", "kill 1234", "pkill -f runserver", "cat .env",
        "python3 x.py", "bash x.sh", "swift build -c release", "npm run build", "make test", "docker run --rm img",
        "sqlite3 db 'select 1'", "git commit -m \"deploy fix\"", "git reset --hard", "ssh h 'cat /srv/.env'",
        "cargo build --release", "swift build && swift test",
    ])
    func whatAGrantStillCovers(command: String) { #expect(holdOf(command) == nil, "\(command)") }
}
