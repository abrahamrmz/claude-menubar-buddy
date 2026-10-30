import Foundation
import Testing
import BuddyCore

@Suite struct OpenCodeBridgeCoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func settings(auto: Bool, allow: AlwaysAllow = AlwaysAllow()) -> OpenCodeBridgeCore.Settings {
        OpenCodeBridgeCore.Settings(autoMode: auto, allowList: allow, paths: ruleContext.paths)
    }
    private func run(_ fixtures: [String], auto: Bool, core: inout OpenCodeBridgeCore) -> [OpenCodeAction] {
        fixtures.flatMap { core.handle(OpenCodeEvent.decode($0)!, settings: settings(auto: auto), now: t0) }
    }

    @Test func autoModePassesAReadAndLogsIt() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.toolCalledShell, OpenCodeFixtures.permissionShell], auto: true, core: &core)
        guard case let .autoReply(sid, rid, log)? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(sid == "ses_1")
        #expect(rid == "per_1")
        #expect(log.agent == "opencode")
        #expect(log.tool == "shell")
        #expect(log.category == "lectura")
        #expect(log.project == "oc-prueba")
        #expect(log.hint.hasPrefix("ls -la notas.txt"))
    }

    @Test func autoModeOffShowsACardWithTheFullCommand() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.toolCalledShell, OpenCodeFixtures.permissionShell], auto: false, core: &core)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.id == "per_1")
        #expect(card.kind == .permission)
        #expect(card.tool == "shell")
        #expect(card.hint == #"ls -la notas.txt 2>&1; echo "---"; cat -A notas.txt 2>&1 | tail -20"#)
        #expect(card.project == "oc-prueba")
        #expect(card.cwd == "/tmp/oc-prueba")
        #expect(card.critical == false)
        #expect(core.pending(id: "per_1") == card)
    }

    @Test func criticalAlwaysShowsACard() {
        var core = OpenCodeBridgeCore()
        let tool = #"{"type":"session.tool.called","data":{"sessionID":"ses_1","id":"call_9","input":{"command":"python3 x.py"}}}"#
        let perm = #"{"type":"permission.asked","location":{"directory":"/tmp/oc-prueba"},"data":{"id":"per_9","sessionID":"ses_1","action":"shell","resources":["python3 x.py"],"source":{"type":"tool","id":"call_9"}}}"#
        let out = run([tool, perm], auto: true, core: &core)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.critical)
        #expect(card.category == "ejecuta")
        #expect(card.reason == "ejecuta código: python3")
    }

    @Test func editCardShowsTheDiff() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.toolCalledEdit, OpenCodeFixtures.permissionEdit], auto: false, core: &core)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.tool == "edit")
        #expect(card.hint == "notas.txt\n+++ pone\nadiós 2")
    }

    @Test func sameRequestTwiceIsOneCard() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.permissionShell, OpenCodeFixtures.permissionShell], auto: false, core: &core)
        #expect(out.count == 1)
    }

    @Test func answeredInTheTerminalWithdrawsTheCard() {
        var core = OpenCodeBridgeCore()
        _ = run([OpenCodeFixtures.permissionShell], auto: false, core: &core)
        #expect(run([OpenCodeFixtures.permissionReplied], auto: false, core: &core) == [.withdrawCard(id: "per_1")])
        #expect(core.pending(id: "per_1") == nil)
        #expect(run([OpenCodeFixtures.permissionReplied], auto: false, core: &core).isEmpty)
    }

    @Test func forgottenRequestsDoNotComeBack() {
        var core = OpenCodeBridgeCore()
        _ = run([OpenCodeFixtures.permissionShell], auto: false, core: &core)
        core.forget(id: "per_1")
        #expect(run([OpenCodeFixtures.permissionShell], auto: false, core: &core).isEmpty)
    }

    @Test func questionFormBecomesAChoiceCard() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.formCreated], auto: true, core: &core)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.kind == .form)
        #expect(card.tool == "question")
        #expect(card.category == "pregunta")
        #expect(card.choices == [OpenCodeChoice(fieldKey: "q0", question: "¿Qué color prefieres?", header: "Color", options: [
            OpenCodeFormOption(value: "Rojo", label: "Rojo", description: "Elegir el color rojo"),
            OpenCodeFormOption(value: "Azul", label: "Azul", description: "Elegir el color azul"),
        ])])
        #expect(run([OpenCodeFixtures.formReplied], auto: true, core: &core) == [.withdrawCard(id: "frm_1")])
    }

    @Test func formsTheCardCannotAnswerStayInTheTerminal() {
        var core = OpenCodeBridgeCore()
        let multi = #"{"type":"form.created","data":{"form":{"id":"frm_2","sessionID":"ses_1","title":"Q","metadata":{"kind":"question"},"fields":[{"key":"q0","type":"multiselect","options":[{"value":"a","label":"a"}]}]}}}"#
        let free = #"{"type":"form.created","data":{"form":{"id":"frm_3","sessionID":"ses_1","title":"Q","metadata":{"kind":"question"},"fields":[{"key":"q0","type":"string"}]}}}"#
        let notQuestion = #"{"type":"form.created","data":{"form":{"id":"frm_4","sessionID":"ses_1","title":"Login","metadata":{"kind":"auth"},"fields":[{"key":"u","type":"string","options":[{"value":"a","label":"a"}]}]}}}"#
        #expect(run([multi, free, notQuestion], auto: false, core: &core).isEmpty)
    }

    @Test func turnFinishedMeasuresTheTurn() {
        var core = OpenCodeBridgeCore()
        _ = core.handle(.executionStarted(sessionID: "ses_1"), settings: settings(auto: false), now: t0)
        let out = core.handle(.executionFinished(sessionID: "ses_1"), settings: settings(auto: false), now: t0.addingTimeInterval(42))
        #expect(out == [.turnFinished(sessionID: "ses_1", elapsed: 42)])
        #expect(core.handle(.executionFinished(sessionID: "ses_1"), settings: settings(auto: false), now: t0).isEmpty)
    }

    @Test func toolInputsAreKeptPerSession() {
        var core = OpenCodeBridgeCore()
        let s = settings(auto: true)
        _ = core.handle(.toolCalled(sessionID: "ses_A", callID: "call_0", input: ["command": "python3 enviar.py"]), settings: s, now: t0)
        _ = core.handle(.toolCalled(sessionID: "ses_B", callID: "call_0", input: ["command": "ls"]), settings: s, now: t0)
        let ask = OpenCodePermissionRequest(id: "per_A", sessionID: "ses_A", action: "shell",
                                            resources: ["python3 enviar.py"], callID: "call_0")
        let out = core.handle(.permissionAsked(ask, directory: "/tmp/oc-prueba"), settings: s, now: t0)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.hint == "python3 enviar.py")
        #expect(card.category == "ejecuta")
    }

    @Test func requestFileHasTheHookShape() throws {
        var core = OpenCodeBridgeCore()
        guard case let .showCard(card)? = run([OpenCodeFixtures.formCreated], auto: false, core: &core).first else {
            Issue.record("no card"); return
        }
        let obj = try JSONSerialization.jsonObject(with: card.requestFileJSON(now: t0)) as! [String: Any]
        #expect(obj["id"] as? String == "frm_1")
        #expect(obj["agent"] as? String == "opencode")
        #expect(obj["tool"] as? String == "question")
        #expect(obj["cwd"] as? String == "/tmp/oc-prueba")
        #expect(obj["project"] as? String == "oc-prueba")
        #expect(obj["ts"] as? Double == 1_000)
        #expect(obj["critical"] as? Bool == false)
        let choices = obj["choices"] as? [[String: Any]]
        #expect(choices?.first?["question"] as? String == "¿Qué color prefieres?")
        #expect((choices?.first?["options"] as? [[String: Any]])?.map { $0["label"] as? String } == ["Rojo", "Azul"])
    }
}
