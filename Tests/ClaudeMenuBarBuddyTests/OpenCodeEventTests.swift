import Foundation
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
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.sessionCreated) == .sessionCreated(sessionID: "ses_1", directory: "/tmp/oc-prueba", parentID: nil))
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

    // MARK: - Session lifecycle (entrega 5)

    @Test func sessionCreatedCarriesItsParent() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.sessionCreatedChild) == .sessionCreated(
            sessionID: "ses_hija", directory: "/tmp/oc-prueba", parentID: "ses_1"))
        #expect(OpenCodeEvent.decode(#"{"type":"session.created","data":{"sessionID":"ses_2","parentID":null}}"#)
                == .sessionCreated(sessionID: "ses_2", directory: nil, parentID: nil))
        #expect(OpenCodeEvent.decode(#"{"type":"session.created","data":{"sessionID":"ses_2","parentID":7}}"#)
                == .sessionCreated(sessionID: "ses_2", directory: nil, parentID: nil))
    }

    @Test func deletedAndArchivedEndTheSession() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.sessionDeleted) == .sessionEnded(sessionID: "ses_1"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.sessionArchived) == .sessionEnded(sessionID: "ses_1"))
    }

    @Test func sessionEndedAcceptsTheThreeShapes() {
        #expect(OpenCodeEvent.decode(#"{"type":"session.deleted","data":{"id":"ses_2"}}"#) == .sessionEnded(sessionID: "ses_2"))
        #expect(OpenCodeEvent.decode(#"{"type":"session.archived","data":{"info":{"id":"ses_3"}}}"#) == .sessionEnded(sessionID: "ses_3"))
        // data.sessionID wins over data.id, which wins over data.info.id.
        #expect(OpenCodeEvent.decode(#"{"type":"session.deleted","data":{"sessionID":"ses_a","id":"ses_b","info":{"id":"ses_c"}}}"#)
                == .sessionEnded(sessionID: "ses_a"))
        #expect(OpenCodeEvent.decode(#"{"type":"session.deleted","data":{"id":"ses_b","info":{"id":"ses_c"}}}"#)
                == .sessionEnded(sessionID: "ses_b"))
        // A field that is not a non-empty string does not count; the next one is tried.
        #expect(OpenCodeEvent.decode(#"{"type":"session.deleted","data":{"sessionID":"","info":{"id":"ses_c"}}}"#)
                == .sessionEnded(sessionID: "ses_c"))
        #expect(OpenCodeEvent.decode(#"{"type":"session.deleted","data":{"sessionID":5}}"#) == .other(type: "session.deleted"))
        #expect(OpenCodeEvent.decode(#"{"type":"session.archived","data":{}}"#) == .other(type: "session.archived"))
        #expect(OpenCodeEvent.decode(#"{"type":"session.unarchived","data":{"sessionID":"ses_1"}}"#) == .other(type: "session.unarchived"))
    }

    @Test func sessionInfoFromTheAPI() {
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_hija", responseBody: Data(OpenCodeFixtures.sessionInfoChild.utf8))
                == .sessionInfo(sessionID: "ses_hija", parentID: "ses_1", archived: false))
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data(OpenCodeFixtures.sessionInfoArchivedRoot.utf8))
                == .sessionInfo(sessionID: "ses_1", parentID: nil, archived: true))
        // The bare Session.Info, as each item of GET /api/session comes.
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data(#"{"id":"ses_1","time":{"created":1}}"#.utf8))
                == .sessionInfo(sessionID: "ses_1", parentID: nil, archived: false))
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data(#"{"data":{"id":"ses_1","parentID":null,"time":{"archived":null}}}"#.utf8))
                == .sessionInfo(sessionID: "ses_1", parentID: nil, archived: false))
    }

    @Test func sessionInfoRejectsWhatItCannotTrust() {
        // Another session's body must never lend its parent to this one.
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_otra", responseBody: Data(OpenCodeFixtures.sessionInfoChild.utf8)) == nil)
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data(#"{"data":{"parentID":"ses_0"}}"#.utf8)) == nil)
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data(#"{"data":{"id":"ses_1","parentID":7}}"#.utf8)) == nil)
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data(#"{"data":{"id":"ses_1","parentID":""}}"#.utf8)) == nil)
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data(#"{"data":[1,2]}"#.utf8)) == nil)
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data("no es json".utf8)) == nil)
        #expect(OpenCodeEvent.sessionInfo(sessionID: "ses_1", responseBody: Data(#"[1,2]"#.utf8)) == nil)
    }
}
