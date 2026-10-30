import Foundation
import Testing
import BuddyCore

@Suite struct OpenCodeAPITests {
    private func file(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString).json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private let service = OpenCodeService.load(from: try! {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString).json")
        try #"{"id":"x","version":"2.1.2","url":"http://127.0.0.1:49374","pid":1,"password":"secreto"}"#
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }())!

    @Test func loadsALoopbackService() {
        #expect(service.baseURL.absoluteString == "http://127.0.0.1:49374")
        #expect(service.authorization == "Basic " + Data("opencode:secreto".utf8).base64EncodedString())
    }

    @Test(arguments: [
        #"{"url":"http://10.0.0.5:49374","password":"p"}"#, #"{"url":"https://127.0.0.1:1","password":"p"}"#,
        #"{"url":"http://evil.com","password":"p"}"#, #"{"password":"p"}"#, #"{"url":"http://127.0.0.1:1"}"#, "no json",
    ])
    func refusesAnythingElse(text: String) throws {
        #expect(OpenCodeService.load(from: try file(text)) == nil)
    }

    @Test func missingFile() {
        #expect(OpenCodeService.load(from: URL(fileURLWithPath: "/nonexistent/service.json")) == nil)
    }

    @Test func requestShapes() throws {
        let get = OpenCodeCall.permissionStillPending(sessionID: "ses_1", requestID: "per_1").urlRequest(service: service)
        #expect(get.httpMethod == "GET")
        #expect(get.url?.absoluteString == "http://127.0.0.1:49374/api/session/ses_1/permission/per_1")
        #expect(get.value(forHTTPHeaderField: "Authorization") == service.authorization)
        #expect(OpenCodeCall.events.urlRequest(service: service).url?.path == "/api/event")
        #expect(OpenCodeCall.sessions(limit: 20).urlRequest(service: service).url?.absoluteString
                == "http://127.0.0.1:49374/api/session?limit=20&order=desc")
        #expect(OpenCodeCall.pendingForms(sessionID: "s").urlRequest(service: service).url?.path == "/api/session/s/form")

        let reply = OpenCodeCall.replyPermission(sessionID: "s", requestID: "r", decision: "reject", message: "no")
            .urlRequest(service: service)
        #expect(reply.httpMethod == "POST")
        #expect(reply.url?.path == "/api/session/s/permission/r/reply")
        #expect(reply.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: reply.httpBody!) as! [String: Any]
        #expect(body["decision"] as? String == "reject")
        #expect(body["message"] as? String == "no")

        let form = OpenCodeCall.replyForm(sessionID: "s", formID: "f", answer: ["q0": "Rojo"]).urlRequest(service: service)
        #expect(form.url?.path == "/api/session/s/form/f/reply")
        let fbody = try JSONSerialization.jsonObject(with: form.httpBody!) as! [String: Any]
        #expect(fbody["answer"] as? [String: String] == ["q0": "Rojo"])
    }

    private func card(_ kind: OpenCodeCardRequest.Kind) -> OpenCodeCardRequest {
        var core = OpenCodeBridgeCore()
        let fixture = kind == .form ? OpenCodeFixtures.formCreated : OpenCodeFixtures.permissionShell
        let out = core.handle(OpenCodeEvent.decode(fixture)!,
                              settings: .init(autoMode: false, allowList: AlwaysAllow(), paths: ruleContext.paths),
                              now: Date())
        guard case let .showCard(c)? = out.first else { fatalError("fixture produced no card") }
        return c
    }

    @Test func answerMapping() {
        let p = card(.permission)
        #expect(OpenCodeAnswer.call(for: p, decision: "allow", reason: nil, answers: nil)
                == .replyPermission(sessionID: "ses_1", requestID: "per_1", decision: "once", message: nil))
        #expect(OpenCodeAnswer.call(for: p, decision: "deny", reason: nil, answers: nil)
                == .replyPermission(sessionID: "ses_1", requestID: "per_1", decision: "reject",
                                    message: "El usuario lo rechazó desde el buddy."))
        #expect(OpenCodeAnswer.call(for: p, decision: "deny", reason: "mejor no", answers: nil)
                == .replyPermission(sessionID: "ses_1", requestID: "per_1", decision: "reject", message: "mejor no"))
        #expect(OpenCodeAnswer.call(for: p, decision: "pass", reason: nil, answers: nil) == nil)

        let f = card(.form)
        #expect(OpenCodeAnswer.call(for: f, decision: "answer", reason: nil, answers: ["¿Qué color prefieres?": "Azul"])
                == .replyForm(sessionID: "ses_1", formID: "frm_1", answer: ["q0": "Azul"]))
        #expect(OpenCodeAnswer.call(for: f, decision: "pass", reason: nil, answers: nil) == nil)
        #expect(OpenCodeAnswer.call(for: f, decision: "deny", reason: nil, answers: nil) == nil)
    }
}
