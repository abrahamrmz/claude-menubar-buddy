import Testing
import BuddyCore

/// Task 1b: what the review of block 1 found still passing on a grant.
@Suite struct SessionHoldReviewTests {
    /// pkill's pattern (and killall -m's) is a regular expression searched in
    /// the process name, or in its whole command line with -f. Any that
    /// reaches the buddy stops it, not only its exact name. ruleContext's home
    /// is /Users/u, so the buddy runs as
    /// /Users/u/Desktop/repos/claude-menubar-buddy/.build/debug/ClaudeMenuBarBuddy.
    @Test(arguments: [
        "pkill -f ClaudeMenu", "pkill -f Buddy", "pkill -f MenuBar", "pkill -f claude", "pkill -if BUDDY",
        "pkill 'Claude.*'", "pkill -9 -f '.'", "pkill -f Desktop/repos", "killall -m '.*Buddy'",
        "killall -m Claude", "pkill -f \"$PATRON\"", "pkill -f '['",
    ])
    func aPatternThatReachesTheBuddyStopsIt(command: String) {
        #expect(holdOf(command) == "puede detener al buddy", "\(command)")
    }

    /// `kill $(…)` takes its PIDs from a search: the search's pattern decides.
    @Test(arguments: [
        "kill -9 $(pgrep -f Buddy)", "kill `pgrep -f claude`", "kill $(pidof ClaudeMenuBarBuddy)",
        "kill $(ps aux | grep Buddy | awk '{print $2}')", "kill -TERM $(pgrep -if menubar)",
    ])
    func aSearchThatFindsTheBuddyStopsIt(command: String) {
        #expect(holdOf(command) == "puede detener al buddy", "\(command)")
    }

    /// `kill -9 -1` signals every process you own, the buddy among them.
    /// A first `-1` is a signal (SIGHUP), not a PID.
    @Test(arguments: ["kill -9 -1", "kill -- -1", "kill -s KILL -1", "kill -HUP -1", "kill -9 1234 -1"])
    func signallingEveryProcessStopsIt(command: String) {
        #expect(holdOf(command) == "puede detener al buddy", "\(command)")
    }

    @Test(arguments: [
        "pkill -f runserver", "pkill node", "pkill -f 'manage.py runserver'", "killall Dock",
        "killall -m '^node$'", "pkill -u abraham node", "kill 1234", "kill -1 1234", "kill -9 $(lsof -ti:8000)",
        "kill $(cat servidor.pid)", "kill $(pgrep -f celery)", "kill -s HUP 1234",
    ])
    func otherSignalsDoNotStopIt(command: String) {
        #expect(holdOf(command) == nil, "\(command)")
    }

    /// Stopping the buddy is a hold, never a new category.
    @Test func theCategoryStaysIrreversible() {
        #expect(category("pkill -f Buddy") == .irreversible)
        #expect(category("kill -9 -1") == .irreversible)
    }

    @Test(arguments: [
        ("glab mr create", "glab"), ("tea pr create", "tea"), ("tailscale funnel 80", "tailscale"),
        ("tailscale serve 80", "tailscale"),
    ])
    func publishingToolsTheRuleDidNotKnow(command: String, name: String) {
        #expect(holdOf(command) == "queda fuera del auto completo: \(name)", "\(command)")
    }
}
