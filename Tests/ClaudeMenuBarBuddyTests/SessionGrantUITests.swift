import Foundation
import Testing
import BuddyCore

@Suite struct SessionGrantUITests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let mexico = TimeZone(secondsFromGMT: -6 * 3600)!
    /// 2026-11-09 14:05:00 UTC.
    private let grantedAt: Double = 1_794_233_100

    private func grant(agent: String = "claude", session: String = "s-1", project: String = "api",
                       trigger: String = "Bash: python3 x.py") -> SessionGrant {
        SessionGrant(agent: agent, sessionID: session, cwd: "/tmp/\(project)", project: project,
                     grantedAt: grantedAt, trigger: trigger)
    }

    private func item(_ id: String, agent: String? = "claude", session: String? = "s-1",
                      coverable: Bool = true, hasChoices: Bool = false) -> GrantSweepItem {
        GrantSweepItem(id: id, agent: agent, session: session, coverable: coverable, hasChoices: hasChoices)
    }

    // MARK: - When the card offers the button (spec 9.1)

    @Test func offeredForACoverableRequestOfAKnownAgentWithAValidSession() {
        #expect(SessionGrantCard.offersGrant(agent: "claude", session: "e575efb6-a7ad-4a1e-ab95-e32b6755393f",
                                             coverable: true, hasChoices: false))
        #expect(SessionGrantCard.offersGrant(agent: "opencode", session: "ses_hija",
                                             coverable: true, hasChoices: false))
        #expect(SessionGrantCard.offersGrant(agent: "claude", session: String(repeating: "a", count: 128),
                                             coverable: true, hasChoices: false))
    }

    @Test func notOfferedWhenTheGrantWouldNotCoverIt() {
        #expect(!SessionGrantCard.offersGrant(agent: "claude", session: "s-1", coverable: false, hasChoices: false))
    }

    @Test func notOfferedForAQuestion() {
        #expect(!SessionGrantCard.offersGrant(agent: "claude", session: "s-1", coverable: true, hasChoices: true))
    }

    @Test func notOfferedForAnUnknownAgent() {
        for agent in [nil, "", "codex", "Claude", "claude "] as [String?] {
            #expect(!SessionGrantCard.offersGrant(agent: agent, session: "s-1", coverable: true, hasChoices: false))
        }
    }

    @Test func notOfferedWithoutAValidSession() {
        let bad: [String?] = [nil, "", "../x", "a/b", "s-1\n", "sesión", "a b", String(repeating: "a", count: 129)]
        for session in bad {
            #expect(!SessionGrantCard.offersGrant(agent: "claude", session: session, coverable: true, hasChoices: false))
        }
    }

    // MARK: - Menu texts (spec 9.2, 9.3)

    @Test func menuTitleCountsSessions() {
        #expect(SessionGrantCard.menuTitle(count: 1) == "Auto completo: 1 sesión")
        #expect(SessionGrantCard.menuTitle(count: 2) == "Auto completo: 2 sesiones")
        #expect(SessionGrantCard.menuTitle(count: 11) == "Auto completo: 11 sesiones")
    }

    @Test func rowTitleNamesProjectAgentTimeAndTrigger() {
        #expect(SessionGrantCard.rowTitle(grant(), timeZone: utc)
                == "api · Claude Code · desde 14:05 · Bash: python3 x.py")
        #expect(SessionGrantCard.rowTitle(grant(agent: "opencode", session: "ses_1", project: "oc-prueba",
                                                trigger: "shell: npm test"), timeZone: utc)
                == "oc-prueba · opencode · desde 14:05 · shell: npm test")
    }

    @Test func rowTitleUsesTheLocalTimeZone() {
        #expect(SessionGrantCard.rowTitle(grant(), timeZone: mexico)
                == "api · Claude Code · desde 08:05 · Bash: python3 x.py")
    }

    @Test func rowTitleWithoutProject() {
        #expect(SessionGrantCard.rowTitle(grant(project: ""), timeZone: utc)
                == "sin proyecto · Claude Code · desde 14:05 · Bash: python3 x.py")
    }

    @Test func rowToolTipSaysLastActivityAndWhenItExpires() {
        // Last activity 16:00 UTC; eight idle hours later is midnight.
        let status = SessionGrantStatus(grant: grant(), lastActivity: Date(timeIntervalSince1970: 1_794_240_000))
        #expect(SessionGrantCard.rowToolTip(status, timeZone: utc)
                == "Última actividad 16:00. Se apaga sola a las 00:00 si la sesión no pide nada. Clic para apagarla ya.")
    }

    @Test func accessibilitySuffixCountsSessions() {
        #expect(SessionGrantCard.accessibilitySuffix(count: 0) == "")
        #expect(SessionGrantCard.accessibilitySuffix(count: 1) == ", 1 sesión en auto completo")
        #expect(SessionGrantCard.accessibilitySuffix(count: 3) == ", 3 sesiones en auto completo")
    }

    // MARK: - The grant a click writes

    @Test func makeGrantKeepsTheFirstLineOfTheHintAsTrigger() {
        let g = SessionGrantCard.makeGrant(agent: "claude", sessionID: "s-1", cwd: "/tmp/api", project: "api",
                                           tool: "Edit", hint: "/tmp/api/a.swift\n--- quita\nx\n+++ pone\ny",
                                           now: Date(timeIntervalSince1970: grantedAt))
        #expect(g == SessionGrant(agent: "claude", sessionID: "s-1", cwd: "/tmp/api", project: "api",
                                  grantedAt: grantedAt, trigger: "Edit: /tmp/api/a.swift"))
    }

    @Test func triggerIsCutAtSixtyCharacters() {
        let long = String(repeating: "a", count: 70)
        #expect(SessionGrantCard.trigger(tool: "Bash", hint: long) == "Bash: " + String(repeating: "a", count: 59) + "…")
        #expect(SessionGrantCard.trigger(tool: "Bash", hint: String(repeating: "b", count: 60))
                == "Bash: " + String(repeating: "b", count: 60))
        #expect(SessionGrantCard.trigger(tool: "Bash", hint: "  ls -la  \nsegunda") == "Bash: ls -la")
        #expect(SessionGrantCard.trigger(tool: "WebFetch", hint: "") == "WebFetch")
    }

    @Test func makeGrantFallsBackToTheFolderName() {
        let fromCwd = SessionGrantCard.makeGrant(agent: "opencode", sessionID: "ses_1", cwd: "/tmp/oc-prueba",
                                                 project: "", tool: "shell", hint: "npm test",
                                                 now: Date(timeIntervalSince1970: grantedAt))
        #expect(fromCwd.project == "oc-prueba")
        #expect(fromCwd.cwd == "/tmp/oc-prueba")
        let nothing = SessionGrantCard.makeGrant(agent: "claude", sessionID: "s-1", cwd: nil, project: nil,
                                                 tool: "Bash", hint: "ls", now: Date(timeIntervalSince1970: grantedAt))
        #expect(nothing.project == "")
        #expect(nothing.cwd == "")
    }

    // MARK: - The queue sweep (spec 9.1 step 3): Claude requests only

    @Test func sweepTakesOnlyTheSameSessionOfTheSameAgent() {
        let items = [
            item("mine"),
            item("other-session", session: "s-2"),
            item("other-agent", agent: "opencode", session: "s-1"),
            item("no-agent", agent: nil),
        ]
        #expect(SessionGrantCard.sweep(items, grants: [grant()]).map(\.id) == ["mine"])
    }

    @Test func sweepLeavesWhatTheButtonWouldNotOffer() {
        let items = [
            item("not-coverable", coverable: false),
            item("question", hasChoices: true),
            item("no-session", session: nil),
            item("bad-session", session: "../s-1"),
        ]
        #expect(SessionGrantCard.sweep(items, grants: [grant()]).isEmpty)
    }

    @Test func sweepWithoutGrantsTakesNothing() {
        #expect(SessionGrantCard.sweep([item("mine")], grants: []).isEmpty)
    }

    @Test func openCodeRequestsAreTheBridgesToSweep() {
        // The bridge sweeps opencode's cards itself, over the session tree it
        // knows; the app's sweep never answers one, even with a matching grant.
        let grants = [grant(agent: "opencode", session: "ses_1"), grant()]
        let items = [item("opencode", agent: "opencode", session: "ses_1"), item("claude")]
        let matches = SessionGrantCard.sweep(items, grants: grants)
        #expect(matches.map(\.id) == ["claude"])
        #expect(matches.map(\.grant) == [grant()])
    }

    @Test func sweepKeepsQueueOrder() {
        let items = [item("c"), item("a"), item("b")]
        #expect(SessionGrantCard.sweep(items, grants: [grant()]).map(\.id) == ["c", "a", "b"])
    }

    // MARK: - What a swept request leaves behind

    @Test func sweptReasonIsTheRuleWording() {
        #expect(SessionGrantCard.sweptReason(category: "ejecuta")
                == "Auto completo de esta sesión (ejecuta) vía Claude Menu Bar Buddy")
    }

    @Test func sweptEntryIsASessionLineOfTheTrail() {
        let entry = SessionGrantCard.sweptEntry(agent: "claude", session: "s-1", project: "api", cwd: "/tmp/api",
                                                tool: "Bash", hint: String(repeating: "x", count: 250),
                                                category: "ejecuta", now: Date(timeIntervalSince1970: grantedAt))
        #expect(entry == AutoLogEntry(ts: grantedAt, agent: "claude", project: "api", cwd: "/tmp/api", tool: "Bash",
                                      hint: String(repeating: "x", count: 200), category: "ejecuta",
                                      grant: "session", session: "s-1"))
    }

    @Test func sweptEntryFillsTheGaps() {
        let entry = SessionGrantCard.sweptEntry(agent: "opencode", session: "ses_hija", project: nil,
                                                cwd: "/tmp/oc-prueba", tool: "shell", hint: "npm test",
                                                category: nil, now: Date(timeIntervalSince1970: grantedAt))
        #expect(entry.project == "oc-prueba")
        #expect(entry.category == "desconocido")
        #expect(entry.grant == "session")
        #expect(entry.session == "ses_hija")
    }
}
