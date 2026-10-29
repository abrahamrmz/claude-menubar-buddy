import Foundation
import Testing
import BuddyCore

@Suite struct AlwaysAllowTests {
    private func file(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aa-\(UUID().uuidString).json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func globalAllowsEverywhere() {
        let list = AlwaysAllow(global: ["git"])
        #expect(list.allows("git", in: "/x"))
        #expect(list.allows("git", in: nil))
        #expect(!list.allows("npm", in: "/x"))
    }

    @Test func projectGrantIsAnExactPath() {
        let list = AlwaysAllow(projects: ["/repo": ["npm"]])
        #expect(list.allows("npm", in: "/repo"))
        #expect(!list.allows("npm", in: "/repo-secrets"))
        #expect(!list.allows("npm", in: nil))
    }

    @Test func readsTheScopedShape() throws {
        let url = try file(#"{"global":["ls"],"projects":{"/r":["jq"]}}"#)
        #expect(AlwaysAllow.read(from: url) == AlwaysAllow(global: ["ls"], projects: ["/r": ["jq"]]))
    }

    @Test func readsABareArrayAsGlobal() throws {
        #expect(AlwaysAllow.read(from: try file(#"["ls"]"#)) == AlwaysAllow(global: ["ls"]))
    }

    @Test(arguments: ["", "{not json", "42", #"{"global":"ls"}"#])
    func malformedFileIsEmpty(text: String) throws {
        let list = AlwaysAllow.read(from: try file(text))
        #expect(list.global.isEmpty)
        #expect(list.projects.isEmpty)
    }

    @Test func missingFileIsEmpty() {
        #expect(AlwaysAllow.read(from: URL(fileURLWithPath: "/nonexistent/aa.json")) == AlwaysAllow())
    }

    @Test(arguments: [("git status", "git"), ("ls -la", "ls"), ("npm test", "npm"), ("./run.sh", "./run.sh")])
    func baseOfAPlainCommand(command: String, base: String) {
        #expect(AlwaysAllow.commandBase(from: command) == base)
    }

    @Test(arguments: [
        "echo hi ; rm -rf ~", "ls | sh", "echo $(whoami)", "cat < /etc/passwd", "a && b",
        "echo `id`", "ls\nrm x", "PATH=/tmp/evil ls", "FOO=1 ls", "ls (x)", "a\\b", "",
    ])
    func noBaseForShapesThatSpeakForMoreThanOneCommand(command: String) {
        #expect(AlwaysAllow.commandBase(from: command) == nil)
    }
}
