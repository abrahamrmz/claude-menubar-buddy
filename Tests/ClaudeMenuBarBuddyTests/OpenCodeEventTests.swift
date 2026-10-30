import Testing
import BuddyCore

@Suite struct OpenCodeEventTests {
    @Test func permissionShell() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.permissionShell) == .permissionAsked(
            OpenCodePermissionRequest(id: "per_1", sessionID: "ses_1", action: "shell",
                                      resources: ["ls -la notas.txt 2>&1", "echo \"---\"", "cat -A notas.txt 2>&1", "tail -20"],
                                      callID: "call_1"),
            directory: "/tmp/oc-prueba"))
    }

    @Test func permissionEditCarriesItsPatch() {
        guard case let .permissionAsked(req, dir)? = OpenCodeEvent.decode(OpenCodeFixtures.permissionEdit) else {
            Issue.record("not decoded"); return
        }
        #expect(dir == "/tmp/oc-prueba")
        #expect(req.action == "edit")
        #expect(req.editedFiles == ["notas.txt"])
        #expect(req.patches.count == 1)
        #expect(req.patches[0].contains("+adiós 2"))
        #expect(req.callID == "call_2")
    }

    @Test func toolCalledKeepsStringInputs() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.toolCalledEdit) == .toolCalled(
            sessionID: "ses_1", callID: "call_2",
            input: ["path": "/tmp/oc-prueba/notas.txt", "oldString": "adiós\n", "newString": "adiós\nadiós 2\n"]))
    }

    @Test func formCreated() {
        guard case let .formCreated(form, dir)? = OpenCodeEvent.decode(OpenCodeFixtures.formCreated) else {
            Issue.record("not decoded"); return
        }
        #expect(dir == "/tmp/oc-prueba")
        #expect(form == OpenCodeForm(id: "frm_1", sessionID: "ses_1", title: "Questions", kind: "question", fields: [
            OpenCodeFormField(key: "q0", title: "Color", description: "¿Qué color prefieres?", type: "string", options: [
                OpenCodeFormOption(value: "Rojo", label: "Rojo", description: "Elegir el color rojo"),
                OpenCodeFormOption(value: "Azul", label: "Azul", description: "Elegir el color azul"),
            ]),
        ]))
    }

    @Test func closingAndLifecycleEvents() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.permissionReplied) == .permissionReplied(sessionID: "ses_1", requestID: "per_1"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.formReplied) == .formClosed(sessionID: "ses_1", formID: "frm_1"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.formCancelled) == .formClosed(sessionID: "ses_1", formID: "frm_1"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.sessionCreated) == .sessionCreated(sessionID: "ses_1", directory: "/tmp/oc-prueba"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.executionStarted) == .executionStarted(sessionID: "ses_1"))
        for f in [OpenCodeFixtures.executionSucceeded, OpenCodeFixtures.executionFailed, OpenCodeFixtures.executionInterrupted] {
            #expect(OpenCodeEvent.decode(f) == .executionFinished(sessionID: "ses_1"))
        }
    }

    @Test func unknownAndBrokenInput() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.textDelta) == .other(type: "session.text.delta"))
        #expect(OpenCodeEvent.decode(#"{"type":"permission.asked","data":{"sessionID":"s"}}"#) == .other(type: "permission.asked"))
        #expect(OpenCodeEvent.decode(#"{"type":"form.created","data":{}}"#) == .other(type: "form.created"))
        #expect(OpenCodeEvent.decode("no es json") == nil)
        #expect(OpenCodeEvent.decode(#"{"data":{}}"#) == nil)
        #expect(OpenCodeEvent.decode(#"[1,2]"#) == nil)
    }
}
