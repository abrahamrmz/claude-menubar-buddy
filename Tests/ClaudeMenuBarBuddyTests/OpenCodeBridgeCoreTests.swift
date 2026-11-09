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

    @Test func pendingCardsListsWhatIsStillWaiting() {
        var core = OpenCodeBridgeCore()
        _ = run([OpenCodeFixtures.toolCalledShell, OpenCodeFixtures.permissionShell], auto: false, core: &core)
        #expect(core.pendingCards.map(\.id) == ["per_1"])
        core.forget(id: "per_1")
        #expect(core.pendingCards.isEmpty)
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

/// The session grant in opencode (entrega 5): a grant on a session covers it and
/// every session below it, and nothing passes while its lineage is unknown.
@Suite struct OpenCodeBridgeSessionGrantTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func settings(_ grants: Set<String>, auto: Bool = false) -> OpenCodeBridgeCore.Settings {
        OpenCodeBridgeCore.Settings(autoMode: auto, allowList: AlwaysAllow(), paths: ruleContext.paths,
                                    sessionGrants: grants)
    }
    private func ask(_ id: String, _ session: String, _ command: String, action: String = "shell") -> OpenCodeEvent {
        .permissionAsked(OpenCodePermissionRequest(id: id, sessionID: session, action: action, resources: [command]),
                         directory: "/tmp/oc-prueba")
    }
    private func info(_ id: String, parent: String?, archived: Bool = false) -> OpenCodeEvent {
        .sessionInfo(sessionID: id, parentID: parent, archived: archived)
    }
    private func sessionLog(_ hint: String, _ category: String, session: String, ts: Double = 1_000,
                            tool: String = "shell") -> AutoLogEntry {
        AutoLogEntry(ts: ts, agent: "opencode", project: "oc-prueba", cwd: "/tmp/oc-prueba", tool: tool,
                     hint: hint, category: category, grant: "session", session: session)
    }
    /// Teaches the core who is whose parent, the way the API would.
    private func learn(_ core: inout OpenCodeBridgeCore, _ links: [(String, String?)]) {
        for (id, parent) in links {
            #expect(core.handle(info(id, parent: parent), settings: settings([]), now: t0).isEmpty)
        }
    }

    // MARK: - Who is covered

    @Test func aDirectGrantPassesWithoutKnowingTheLineage() {
        var core = OpenCodeBridgeCore()
        let out = core.handle(ask("per_g1", "ses_1", "python3 x.py"), settings: settings(["ses_1"]), now: t0)
        #expect(out == [.autoReply(sessionID: "ses_1", requestID: "per_g1",
                                   log: sessionLog("python3 x.py", "ejecuta", session: "ses_1")),
                        .touchSessionGrant(sessionID: "ses_1")])
        #expect(core.pending(id: "per_g1") == nil)
        #expect(core.handle(ask("per_g1", "ses_1", "python3 x.py"), settings: settings(["ses_1"]), now: t0).isEmpty)
    }

    @Test func aChildWithAKnownParentPasses() {
        var core = OpenCodeBridgeCore()
        #expect(core.handle(OpenCodeEvent.decode(OpenCodeFixtures.sessionCreatedChild)!, settings: settings([]), now: t0).isEmpty)
        let out = core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: settings(["ses_1"]), now: t0)
        #expect(out == [.autoReply(sessionID: "ses_hija", requestID: "per_h",
                                   log: sessionLog("python3 x.py", "ejecuta", session: "ses_hija")),
                        .touchSessionGrant(sessionID: "ses_1")])
    }

    @Test func aGrandchildPasses() {
        var core = OpenCodeBridgeCore()
        learn(&core, [("ses_nieta", "ses_hija"), ("ses_hija", "ses_1"), ("ses_1", nil)])
        let out = core.handle(ask("per_n", "ses_nieta", "rm -rf build"), settings: settings(["ses_1"]), now: t0)
        #expect(out == [.autoReply(sessionID: "ses_nieta", requestID: "per_n",
                                   log: sessionLog("rm -rf build", "irreversible", session: "ses_nieta")),
                        .touchSessionGrant(sessionID: "ses_1")])
        #expect(core.rootIfKnown("ses_nieta") == "ses_1")
        #expect(core.grantSessionID(for: "ses_nieta") == "ses_1")
    }

    @Test func aSessionOfAnotherTreeIsNotCovered() {
        var core = OpenCodeBridgeCore()
        learn(&core, [("ses_otra", nil)])
        let out = core.handle(ask("per_o", "ses_otra", "python3 x.py"), settings: settings(["ses_1"]), now: t0)
        guard case let .showCard(card)? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(card.sessionCoverable)
    }

    @Test func webPassesWithAGrantAndOnlyThen() {
        var core = OpenCodeBridgeCore()
        let out = core.handle(ask("per_w", "ses_1", "https://example.com", action: "webfetch"),
                              settings: settings(["ses_1"]), now: t0)
        #expect(out == [.autoReply(sessionID: "ses_1", requestID: "per_w",
                                   log: sessionLog("webfetch\nhttps://example.com", "sale", session: "ses_1",
                                                   tool: "webfetch")),
                        .touchSessionGrant(sessionID: "ses_1")])
        var plain = OpenCodeBridgeCore()
        let card = plain.handle(ask("per_w", "ses_1", "https://example.com", action: "webfetch"),
                                settings: settings([], auto: true), now: t0)
        guard case .showCard? = card.first, card.count == 1 else { Issue.record("\(card)"); return }
    }

    @Test func externalDirectoryAndUnknownToolsNeverPass() {
        var core = OpenCodeBridgeCore()
        for (id, action) in [("per_e", "external_directory"), ("per_m", "mcp_publicar")] {
            let out = core.handle(ask(id, "ses_1", "/Users/u/otro/*", action: action), settings: settings(["ses_1"]), now: t0)
            guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); continue }
            #expect(card.sessionCoverable == false)
            // Any verdict renews the grant's activity.
            #expect(out.dropFirst() == [.touchSessionGrant(sessionID: "ses_1")])
        }
    }

    @Test func shellThatLeavesTheMachineNeverPassesNorWaits() {
        var core = OpenCodeBridgeCore()
        let out = core.handle(ask("per_c", "ses_1", "curl https://example.com"), settings: settings(["ses_1"]), now: t0)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.category == "sale")
        #expect(card.sessionCoverable == false)
        #expect(out.dropFirst() == [.touchSessionGrant(sessionID: "ses_1")])
        // Not coverable: no wait and no lineage request, even with an unknown parent.
        let child = core.handle(ask("per_c2", "ses_hija", "curl https://example.com"), settings: settings(["ses_1"]), now: t0)
        guard case .showCard? = child.first, child.count == 1 else { Issue.record("\(child)"); return }
    }

    @Test func aFormNeverPasses() {
        var core = OpenCodeBridgeCore()
        let out = core.handle(OpenCodeEvent.decode(OpenCodeFixtures.formCreated)!, settings: settings(["ses_1"]), now: t0)
        guard case let .showCard(card)? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(card.kind == .form)
        #expect(card.sessionCoverable == false)
    }

    @Test func autoModeStillPassesFirstAndNeverWaits() {
        var core = OpenCodeBridgeCore()
        let granted = core.handle(ask("per_l", "ses_1", "ls"), settings: settings(["ses_1"], auto: true), now: t0)
        #expect(granted == [.autoReply(sessionID: "ses_1", requestID: "per_l",
                                       log: AutoLogEntry(ts: 1_000, agent: "opencode", project: "oc-prueba",
                                                         cwd: "/tmp/oc-prueba", tool: "shell", hint: "ls",
                                                         category: "lectura", grant: "auto", session: "ses_1")),
                            .touchSessionGrant(sessionID: "ses_1")])
        // Passed by auto mode with an unknown lineage: nothing to wait for, nothing to touch.
        let child = core.handle(ask("per_l2", "ses_hija", "ls"), settings: settings(["ses_1"], auto: true), now: t0)
        guard case let .autoReply(_, _, log)? = child.first, child.count == 1 else { Issue.record("\(child)"); return }
        #expect(log.grant == "auto")
        #expect(log.session == "ses_hija")
    }

    // MARK: - Unknown lineage

    @Test func anUnknownParentWaitsAsksAndPassesWhenTheAnswerComes() {
        var core = OpenCodeBridgeCore()
        let s = settings(["ses_1"])
        #expect(core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: s, now: t0)
                == [.resolveLineage(sessionID: "ses_hija")])
        #expect(core.pending(id: "per_h") == nil)
        #expect(core.pendingCards.isEmpty)
        #expect(core.handle(info("ses_hija", parent: "ses_1"), settings: s, now: t0.addingTimeInterval(0.5))
                == [.autoReply(sessionID: "ses_hija", requestID: "per_h",
                               log: sessionLog("python3 x.py", "ejecuta", session: "ses_hija", ts: 1_000.5)),
                    .touchSessionGrant(sessionID: "ses_1")])
        // Exactly once.
        #expect(core.handle(info("ses_hija", parent: "ses_1"), settings: s, now: t0.addingTimeInterval(0.6)).isEmpty)
        #expect(core.handle(.lineageUnavailable(sessionID: "ses_hija"), settings: s, now: t0.addingTimeInterval(3)).isEmpty)
    }

    @Test func eachMissingLinkIsAskedInTurn() {
        var core = OpenCodeBridgeCore()
        let s = settings(["ses_1"])
        #expect(core.handle(ask("per_n", "ses_nieta", "python3 x.py"), settings: s, now: t0)
                == [.resolveLineage(sessionID: "ses_nieta")])
        #expect(core.handle(info("ses_nieta", parent: "ses_hija"), settings: s, now: t0.addingTimeInterval(0.5))
                == [.resolveLineage(sessionID: "ses_hija")])
        let out = core.handle(info("ses_hija", parent: "ses_1"), settings: s, now: t0.addingTimeInterval(1))
        guard case let .autoReply(_, requestID, log)? = out.first else { Issue.record("\(out)"); return }
        #expect(requestID == "per_n")
        #expect(log.grant == "session")
    }

    @Test func lineageUnavailableGivesACard() {
        var core = OpenCodeBridgeCore()
        let s = settings(["ses_1"])
        _ = core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: s, now: t0)
        #expect(core.handle(.lineageUnavailable(sessionID: "ses_otra"), settings: s, now: t0).isEmpty)
        let out = core.handle(.lineageUnavailable(sessionID: "ses_hija"), settings: s, now: t0.addingTimeInterval(0.1))
        guard case let .showCard(card)? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(card.id == "per_h")
        #expect(card.category == "ejecuta")
        #expect(card.sessionCoverable)
        #expect(core.pending(id: "per_h") == card)
    }

    @Test func aGoneSessionGivesACardAndRevokesOnlyAGrantedOne() {
        var core = OpenCodeBridgeCore()
        let s = settings(["ses_1"])
        _ = core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: s, now: t0)
        let out = core.handle(.sessionGone(sessionID: "ses_hija"), settings: s, now: t0.addingTimeInterval(0.1))
        guard case let .showCard(card)? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(card.id == "per_h")
        #expect(core.handle(.sessionGone(sessionID: "ses_1"), settings: s, now: t0) == [.revokeSessionGrant(sessionID: "ses_1")])
        #expect(core.handle(.sessionGone(sessionID: "ses_2"), settings: s, now: t0).isEmpty)
        // A session known to be gone is not asked about again: its next request is a card at once.
        let again = core.handle(ask("per_h2", "ses_hija", "python3 x.py"), settings: s, now: t0.addingTimeInterval(1))
        guard case .showCard? = again.first, again.count == 1 else { Issue.record("\(again)"); return }
    }

    @Test func theWaitEndsAfterTwoSecondsInTotal() {
        var core = OpenCodeBridgeCore()
        let s = settings(["ses_1"])
        let delta = OpenCodeEvent.other(type: "session.text.delta")
        #expect(core.handle(ask("per_n", "ses_nieta", "python3 x.py"), settings: s, now: t0)
                == [.resolveLineage(sessionID: "ses_nieta")])
        #expect(core.handle(delta, settings: s, now: t0.addingTimeInterval(1.9)).isEmpty)
        // A second hop does not restart the clock.
        #expect(core.handle(info("ses_nieta", parent: "ses_hija"), settings: s, now: t0.addingTimeInterval(1))
                == [.resolveLineage(sessionID: "ses_hija")])
        let out = core.handle(delta, settings: s, now: t0.addingTimeInterval(OpenCodeBridgeCore.lineageWait))
        guard case let .showCard(card)? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(card.id == "per_n")
        // Too late: the answer no longer approves it. The card stays, and the next link is
        // asked so the root is known if the user clicks.
        #expect(core.handle(info("ses_hija", parent: "ses_1"), settings: s, now: t0.addingTimeInterval(2.5))
                == [.resolveLineage(sessionID: "ses_1")])
        #expect(core.pending(id: "per_n") == card)
    }

    @Test func heldRequestsAreNeitherDuplicatedNorLost() {
        var core = OpenCodeBridgeCore()
        let s = settings(["ses_1"])
        #expect(core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: s, now: t0)
                == [.resolveLineage(sessionID: "ses_hija")])
        // The same request again (a reconnect recovers it) and a second one from the same session.
        #expect(core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: s, now: t0.addingTimeInterval(0.1)).isEmpty)
        #expect(core.handle(ask("per_h2", "ses_hija", "make test"), settings: s, now: t0.addingTimeInterval(0.2)).isEmpty)
        #expect(core.handle(info("ses_hija", parent: "ses_1"), settings: s, now: t0.addingTimeInterval(0.5))
                == [.autoReply(sessionID: "ses_hija", requestID: "per_h",
                               log: sessionLog("python3 x.py", "ejecuta", session: "ses_hija", ts: 1_000.5)),
                    .touchSessionGrant(sessionID: "ses_1"),
                    .autoReply(sessionID: "ses_hija", requestID: "per_h2",
                               log: sessionLog("make test", "ejecuta", session: "ses_hija", ts: 1_000.5)),
                    .touchSessionGrant(sessionID: "ses_1")])
        #expect(core.handle(ask("per_h2", "ses_hija", "make test"), settings: s, now: t0.addingTimeInterval(1)).isEmpty)
    }

    @Test func aHeldRequestAnsweredElsewhereIsDropped() {
        let s = settings(["ses_1"])
        var core = OpenCodeBridgeCore()
        _ = core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: s, now: t0)
        #expect(core.handle(.permissionReplied(sessionID: "ses_hija", requestID: "per_h"), settings: s, now: t0).isEmpty)
        #expect(core.handle(info("ses_hija", parent: "ses_1"), settings: s, now: t0.addingTimeInterval(0.5)).isEmpty)
        #expect(core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: s, now: t0.addingTimeInterval(1)).isEmpty)

        var forgotten = OpenCodeBridgeCore()
        _ = forgotten.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: s, now: t0)
        forgotten.forget(id: "per_h")
        #expect(forgotten.handle(info("ses_hija", parent: "ses_1"), settings: s, now: t0.addingTimeInterval(0.5)).isEmpty)
    }

    @Test func aCycleInTheParentsGivesACard() {
        var core = OpenCodeBridgeCore()
        learn(&core, [("ses_a", "ses_b"), ("ses_b", "ses_a"), ("ses_c", "ses_c")])
        for (id, session) in [("per_a", "ses_a"), ("per_c", "ses_c")] {
            let out = core.handle(ask(id, session, "python3 x.py"), settings: settings(["ses_1"]), now: t0)
            guard case .showCard? = out.first, out.count == 1 else { Issue.record("\(out)"); continue }
        }
        #expect(core.rootIfKnown("ses_a") == nil)
        #expect(core.grantSessionID(for: "ses_a") == "ses_a")
    }

    @Test func moreThanEightLevelsGivesACard() {
        var core = OpenCodeBridgeCore()
        learn(&core, [("ses_n0", nil)] + (1...9).map { ("ses_n\($0)", "ses_n\($0 - 1)") })
        let eight = core.handle(ask("per_8", "ses_n8", "python3 x.py"), settings: settings(["ses_n0"]), now: t0)
        guard case .autoReply? = eight.first else { Issue.record("\(eight)"); return }
        #expect(eight.dropFirst() == [.touchSessionGrant(sessionID: "ses_n0")])
        let nine = core.handle(ask("per_9", "ses_n9", "python3 x.py"), settings: settings(["ses_n0"]), now: t0)
        guard case .showCard? = nine.first, nine.count == 1 else { Issue.record("\(nine)"); return }
        #expect(core.rootIfKnown("ses_n8") == "ses_n0")
        #expect(core.rootIfKnown("ses_n9") == nil)
        #expect(core.grantSessionID(for: "ses_n9") == "ses_n9")
    }

    @Test func anInvalidSessionIDIsNeverAskedAbout() {
        var core = OpenCodeBridgeCore()
        let out = core.handle(ask("per_x", "ses/../x", "python3 x.py"), settings: settings(["ses_1"]), now: t0)
        guard case .showCard? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(core.lineageRequest(forCard: "per_x", now: t0) == nil)
    }

    // MARK: - End of a session

    @Test func endingASessionRevokesOnlyAGrantedOne() {
        var core = OpenCodeBridgeCore()
        let s = settings(["ses_1"])
        #expect(core.handle(OpenCodeEvent.decode(OpenCodeFixtures.sessionDeleted)!, settings: s, now: t0)
                == [.revokeSessionGrant(sessionID: "ses_1")])
        #expect(core.handle(OpenCodeEvent.decode(OpenCodeFixtures.sessionArchived)!, settings: s, now: t0)
                == [.revokeSessionGrant(sessionID: "ses_1")])
        #expect(core.handle(.sessionEnded(sessionID: "ses_2"), settings: s, now: t0).isEmpty)
        #expect(core.handle(OpenCodeEvent.decode(OpenCodeFixtures.sessionDeleted)!, settings: settings([]), now: t0).isEmpty)
        // What the API says when the bridge connects: archived revokes, alive does not.
        #expect(core.handle(info("ses_1", parent: nil, archived: true), settings: s, now: t0)
                == [.revokeSessionGrant(sessionID: "ses_1")])
        #expect(core.handle(info("ses_1", parent: nil), settings: s, now: t0).isEmpty)
        #expect(core.handle(info("ses_2", parent: nil, archived: true), settings: s, now: t0).isEmpty)
    }

    @Test func aGrantRevokedByAnEventCoversNothingInThatEvent() {
        var core = OpenCodeBridgeCore()
        _ = core.handle(ask("per_x", "ses_x", "python3 x.py"), settings: settings(["ses_1"]), now: t0)
        let out = core.handle(info("ses_x", parent: nil, archived: true), settings: settings(["ses_1", "ses_x"]),
                              now: t0.addingTimeInterval(0.5))
        guard out.count == 2, case let .showCard(card) = out[1] else { Issue.record("\(out)"); return }
        #expect(out[0] == .revokeSessionGrant(sessionID: "ses_x"))
        #expect(card.id == "per_x")
    }

    // MARK: - Without grants

    @Test func withoutGrantsNothingWaitsAndTheCardSaysWhetherItIsCoverable() throws {
        var core = OpenCodeBridgeCore()
        let out = core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: settings([]), now: t0)
        guard case let .showCard(card)? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(card.sessionCoverable)
        let obj = try JSONSerialization.jsonObject(with: card.requestFileJSON(now: t0)) as! [String: Any]
        #expect(obj["session"] as? String == "ses_hija")
        #expect(obj["session_coverable"] as? Bool == true)

        let curl = core.handle(ask("per_c", "ses_1", "curl https://example.com"), settings: settings([]), now: t0)
        guard case let .showCard(curlCard)? = curl.first else { Issue.record("\(curl)"); return }
        let curlObj = try JSONSerialization.jsonObject(with: curlCard.requestFileJSON(now: t0)) as! [String: Any]
        #expect(curlObj["session_coverable"] as? Bool == false)

        let form = core.handle(OpenCodeEvent.decode(OpenCodeFixtures.formCreated)!, settings: settings([]), now: t0)
        guard case let .showCard(formCard)? = form.first else { Issue.record("\(form)"); return }
        let formObj = try JSONSerialization.jsonObject(with: formCard.requestFileJSON(now: t0)) as! [String: Any]
        #expect(formObj["session"] as? String == "ses_1")
        #expect(formObj["session_coverable"] as? Bool == false)
    }

    @Test func aCoverableCardAsksForItsLineageWithoutWaiting() {
        var core = OpenCodeBridgeCore()
        _ = core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: settings([]), now: t0)
        #expect(core.grantSessionID(for: "ses_hija") == "ses_hija")
        #expect(core.lineageRequest(forCard: "per_h", now: t0) == "ses_hija")
        #expect(core.lineageRequest(forCard: "per_h", now: t0.addingTimeInterval(1)) == nil)
        #expect(core.lineageRequest(forCard: "per_h", now: t0.addingTimeInterval(2)) == "ses_hija")
        #expect(core.handle(info("ses_hija", parent: "ses_1"), settings: settings([]), now: t0.addingTimeInterval(2.1))
                == [.resolveLineage(sessionID: "ses_1")])
        #expect(core.lineageRequest(forCard: "per_h", now: t0.addingTimeInterval(2.2)) == nil)
        #expect(core.handle(info("ses_1", parent: nil), settings: settings([]), now: t0.addingTimeInterval(2.3)).isEmpty)
        #expect(core.lineageRequest(forCard: "per_h", now: t0.addingTimeInterval(5)) == nil)
        #expect(core.grantSessionID(for: "ses_hija") == "ses_1")
        // Not coverable, a form, or no such card: nothing to ask.
        _ = core.handle(ask("per_c", "ses_otra", "curl https://example.com"), settings: settings([]), now: t0)
        _ = core.handle(OpenCodeEvent.decode(OpenCodeFixtures.formCreated)!, settings: settings([]), now: t0)
        #expect(core.lineageRequest(forCard: "per_c", now: t0) == nil)
        #expect(core.lineageRequest(forCard: "frm_1", now: t0) == nil)
        #expect(core.lineageRequest(forCard: "per_nada", now: t0) == nil)
    }

    // MARK: - Sweep

    @Test func theSweepApprovesASiblingAndLeavesAnotherRoot() {
        var core = OpenCodeBridgeCore()
        learn(&core, [("ses_h1", "ses_1"), ("ses_h2", "ses_1"), ("ses_1", nil), ("ses_z", "ses_9"), ("ses_9", nil)])
        for (id, session, command) in [("per_h1", "ses_h1", "python3 x.py"), ("per_h2", "ses_h2", "python3 x.py"),
                                       ("per_c", "ses_h2", "curl https://example.com"), ("per_z", "ses_z", "python3 x.py")] {
            _ = core.handle(ask(id, session, command), settings: settings([]), now: t0)
        }
        _ = core.handle(OpenCodeEvent.decode(OpenCodeFixtures.formCreated)!, settings: settings([]), now: t0)
        #expect(core.sweep(settings: settings([]), now: t0).isEmpty)
        #expect(core.sweep(settings: settings(["ses_1"]), now: t0.addingTimeInterval(5), excluding: "per_h1")
                == [.autoReply(sessionID: "ses_h2", requestID: "per_h2",
                               log: sessionLog("python3 x.py", "ejecuta", session: "ses_h2", ts: 1_005)),
                    .withdrawCard(id: "per_h2")])
        #expect(core.pendingCards.map(\.id).sorted() == ["frm_1", "per_c", "per_h1", "per_z"])
        #expect(core.sweep(settings: settings(["ses_1"]), now: t0.addingTimeInterval(6))
                == [.autoReply(sessionID: "ses_h1", requestID: "per_h1",
                               log: sessionLog("python3 x.py", "ejecuta", session: "ses_h1", ts: 1_006)),
                    .withdrawCard(id: "per_h1")])
        #expect(core.sweep(settings: settings(["ses_1"]), now: t0.addingTimeInterval(7)).isEmpty)
    }

    @Test func theSweepAsksForAnUnknownLineageAndApprovesOnceItArrives() {
        var core = OpenCodeBridgeCore()
        _ = core.handle(ask("per_h", "ses_hija", "python3 x.py"), settings: settings([]), now: t0)
        let s = settings(["ses_1"])
        #expect(core.sweep(settings: s, now: t0) == [.resolveLineage(sessionID: "ses_hija")])
        #expect(core.sweep(settings: s, now: t0.addingTimeInterval(1)).isEmpty)
        #expect(core.handle(info("ses_hija", parent: "ses_1"), settings: s, now: t0.addingTimeInterval(1.5))
                == [.resolveLineage(sessionID: "ses_1")])
        #expect(core.sweep(settings: s, now: t0.addingTimeInterval(2))
                == [.autoReply(sessionID: "ses_hija", requestID: "per_h",
                               log: sessionLog("python3 x.py", "ejecuta", session: "ses_hija", ts: 1_002)),
                    .withdrawCard(id: "per_h")])
    }
}
