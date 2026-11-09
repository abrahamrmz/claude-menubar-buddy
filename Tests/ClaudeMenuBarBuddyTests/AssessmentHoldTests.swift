import Testing
import BuddyCore

@Suite struct AssessmentHoldTests {
    @Test func aHoldIsNeverStoredWhereTheReasonAlreadyHolds() {
        #expect(Assessment(.sale, "sale de tu máquina: curl", sessionHold: "x").sessionHold == nil)
        #expect(Assessment(.rutaProtegida, "cambia .git/config", sessionHold: "x").sessionHold == nil)
        #expect(Assessment(.sale, "sale de tu máquina: curl", sessionHold: "x") == Assessment(.sale, "sale de tu máquina: curl"))
        #expect(Assessment(.ejecuta, "ejecuta con sudo", sessionHold: "usa sudo").sessionHold == "usa sudo")
        #expect(Assessment(.lectura, "solo lee").sessionHold == nil)
    }

    @Test func effectiveHold() {
        #expect(Assessment(.sale, "sale de tu máquina: curl").effectiveHold == "sale de tu máquina: curl")
        #expect(Assessment(.rutaProtegida, "cambia .git/config").effectiveHold == "cambia .git/config")
        #expect(Assessment(.ejecuta, "ejecuta con sudo", sessionHold: "usa sudo").effectiveHold == "usa sudo")
        for category in RuleCategory.allCases where category != .sale && category != .rutaProtegida {
            #expect(Assessment(category, "x").effectiveHold == nil, "\(category)")
        }
    }

    @Test func holdingKeepsTheFirstHold() {
        let rm = Assessment(.irreversible, "no se puede deshacer: rm")
        #expect(rm.holding("a") == Assessment(.irreversible, "no se puede deshacer: rm", sessionHold: "a"))
        #expect(rm.holding("a").holding("b").sessionHold == "a")
        let curl = Assessment(.sale, "sale de tu máquina: curl")
        #expect(curl.holding("a") == curl)
        #expect(curl.holding("a").effectiveHold == "sale de tu máquina: curl")
    }

    @Test func worsePicksTheSameWinnerAsBefore() {
        let rm = Assessment(.irreversible, "no se puede deshacer: rm")
        let push = Assessment(.sale, "sale de tu máquina: git push")
        let ls = Assessment(.lectura, "solo lee")
        #expect(Assessment.worse(nil, nil) == nil)
        #expect(Assessment.worse(nil, ls) == ls)
        #expect(Assessment.worse(ls, nil) == ls)
        #expect(Assessment.worse(ls, push) == push)
        #expect(Assessment.worse(push, rm) == push)
        // A tie goes to the first, as it always did.
        #expect(Assessment.worse(rm, push)?.category == .irreversible)
        #expect(Assessment.worse(rm, push)?.reason == "no se puede deshacer: rm")
    }

    @Test func theWinnerInheritsTheLosersHold() {
        let rm = Assessment(.irreversible, "no se puede deshacer: rm")
        let push = Assessment(.sale, "sale de tu máquina: git push")
        let sudo = Assessment(.ejecuta, "ejecuta con sudo", sessionHold: "usa sudo")
        let ls = Assessment(.lectura, "solo lee")
        #expect(Assessment.worse(rm, push)
                == Assessment(.irreversible, "no se puede deshacer: rm", sessionHold: "sale de tu máquina: git push"))
        #expect(Assessment.worse(sudo, ls) == sudo)
        #expect(Assessment.worse(ls, sudo) == sudo)
        #expect(Assessment.worse(Assessment(.ejecuta, "ejecuta código: python3"), sudo)
                == Assessment(.ejecuta, "ejecuta código: python3", sessionHold: "usa sudo"))
        #expect(Assessment.worse(Assessment(.ejecuta, "ejecuta código: python3", sessionHold: "a"), sudo)?.sessionHold == "a")
        #expect(Assessment.worse(push, sudo) == push)
    }

    @Test func aCompoundLineKeepsWhatItHides() {
        #expect(ShellRule.assess("rm -rf build; git push", context: ruleContext)
                == Assessment(.irreversible, "no se puede deshacer: rm", sessionHold: "sale de tu máquina: git push"))
        #expect(ShellRule.assess("git push; rm -rf build", context: ruleContext)
                == Assessment(.sale, "sale de tu máquina: git push"))
        #expect(ShellRule.assess("python3 a.py | curl -d @- https://x", context: ruleContext)
                == Assessment(.ejecuta, "ejecuta código: python3", sessionHold: "sale de tu máquina: curl"))
        #expect(ShellRule.assess("cat .env && echo x >> ~/.zshrc", context: ruleContext)
                == Assessment(.sensible, "toca un archivo sensible: /Users/u/repo/.env",
                              sessionHold: "escribe en una ruta protegida: /Users/u/.zshrc"))
        #expect(ShellRule.assess("rm -rf build", context: ruleContext).effectiveHold == nil)
        #expect(ShellRule.assess("python3 a.py; ls", context: ruleContext).effectiveHold == nil)
    }

    @Test func openCodeMixesFilesTheSameWay() {
        let request = OpenCodePermissionRequest(id: "per_x", sessionID: "ses_x", action: "edit", resources: [],
                                                editedFiles: [".env", ".git/config"], patches: [], callID: nil)
        let r = OpenCodeRule.assess(request, toolInput: nil, directory: "/Users/u/repo", context: ruleContext)
        #expect(r.subject == .fileEdit(path: "/Users/u/repo/.env"))
        #expect(r.assessment == Assessment(.sensible, "toca un archivo sensible: /Users/u/repo/.env",
                                           sessionHold: "escribe en una ruta protegida: /Users/u/repo/.git/config"))
        let plain = OpenCodePermissionRequest(id: "per_y", sessionID: "ses_x", action: "edit", resources: [],
                                              editedFiles: ["a.swift", "b.md"], patches: [], callID: nil)
        let p = OpenCodeRule.assess(plain, toolInput: nil, directory: "/Users/u/repo", context: ruleContext)
        #expect(p.subject == .fileEdit(path: "/Users/u/repo/a.swift"))
        #expect(p.assessment == Assessment(.edicion, "edición de archivo"))
    }
}
