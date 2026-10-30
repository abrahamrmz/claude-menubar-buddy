import Testing
import BuddyCore

@Suite struct OpenCodeConfigCheckTests {
    private let recommended = """
    {
      "$schema": "https://opencode.ai/config.json",
      // the buddy decides
      "permissions": [
        { "action": "shell", "resource": "*", "effect": "ask" },
        { "action": "edit",  "resource": "*", "effect": "ask" },
        { "action": "shell", "resource": "git status *", "effect": "allow" }, /* specific rules don't count */
      ],
    }
    """

    @Test func recommendedConfigAsks() {
        #expect(OpenCodeConfigCheck.effect(of: "shell", inConfig: recommended) == "ask")
        #expect(OpenCodeConfigCheck.asksForShellAndEdit(configText: recommended))
    }

    @Test func noPermissionsMeansNothingAsks() {
        #expect(OpenCodeConfigCheck.effect(of: "shell", inConfig: #"{"provider":{}}"#) == nil)
        #expect(!OpenCodeConfigCheck.asksForShellAndEdit(configText: #"{"provider":{}}"#))
    }

    @Test func lastMatchWins() {
        let text = #"{"permissions":[{"action":"shell","resource":"*","effect":"ask"},{"action":"*","resource":"*","effect":"allow"},{"action":"edit","resource":"*","effect":"ask"}]}"#
        #expect(OpenCodeConfigCheck.effect(of: "shell", inConfig: text) == "allow")
        #expect(OpenCodeConfigCheck.effect(of: "edit", inConfig: text) == "ask")
        #expect(!OpenCodeConfigCheck.asksForShellAndEdit(configText: text))
    }

    @Test func commentsInsideStringsAreText() {
        let text = #"{"permissions":[{"action":"shell","resource":"*","effect":"ask","note":"http://x // no"},{"action":"edit","resource":"*","effect":"ask"}]}"#
        #expect(OpenCodeConfigCheck.asksForShellAndEdit(configText: text))
    }

    @Test func garbageIsNotAsking() {
        #expect(!OpenCodeConfigCheck.asksForShellAndEdit(configText: "{ roto"))
    }
}
