import AppKit

// "Take me to the session that's asking" — the one thing Masko did that the
// card alone can't replace: some decisions (a long plan, a diff you want to
// read in context) belong in the editor, not on a 430pt panel.
//
// The hook captures who hosts the session (host_bundle / term_program) and
// where it lives (cwd); this file turns that into a focused window. It is the
// ONLY place in the app that deliberately steals focus, and only ever from an
// explicit user action (⌘M or the card's window button) — the card itself
// stays non-activating and stays up, still pending, after the jump.
extension AppDelegate {
    /// Apps that can raise the window ALREADY showing a given folder when
    /// asked via `open -b <bundle> <path>`. That's the whole trick behind
    /// multi-window targeting without Accessibility permissions: two VS Code
    /// windows on two repos, and the one holding this session's cwd comes
    /// forward. Terminals aren't in here — passing a path to those opens a
    /// NEW window, which is the opposite of what the user asked for.
    static let folderTargetingEditors: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",
        "dev.zed.Zed",
    ]

    /// TERM_PROGRAM → bundle id, for the case where the terminal didn't pass
    /// __CFBundleIdentifier down (a shell started outside the .app, some
    /// multiplexer setups). Only well-known values; anything else falls
    /// through to "no jump target" rather than to a wrong window.
    static let termProgramBundles: [String: String] = [
        "iTerm.app": "com.googlecode.iterm2",
        "Apple_Terminal": "com.apple.Terminal",
        "ghostty": "com.mitchellh.ghostty",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "Hyper": "co.zeit.hyper",
        "WezTerm": "com.github.wez.wezterm",
        "Tabby": "org.tabby",
        "vscode": "com.microsoft.VSCode",
        "kitty": "net.kovidgoyal.kitty",
        "alacritty": "org.alacritty",
    ]

    /// The bundle id to raise for a request, plus a human name for the
    /// button's tooltip. nil = nothing to jump to (ssh/tmux, an old hook, or
    /// a host app that isn't installed anymore) → the UI hides the button.
    func jumpTarget(for req: PendingRequest?) -> (bundle: String, name: String)? {
        guard let req = req else { return nil }
        var bundle = req.hostBundle ?? ""
        if bundle.isEmpty, let term = req.termProgram, !term.isEmpty {
            bundle = AppDelegate.termProgramBundles[term] ?? ""
        }
        guard !bundle.isEmpty else { return nil }
        // Ask Launch Services for the real app name ("Visual Studio Code",
        // "iTerm") instead of hardcoding a second lookup table — and use the
        // miss as the is-it-still-installed check.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        return (bundle, url.deletingPathExtension().lastPathComponent)
    }

    /// Raise the host window for the request currently on the card. The card
    /// is untouched: the request stays pending, the hotkeys stay live (they
    /// are global), so the usual move is ⌘M → read it in context → ⌘⏎.
    @objc func jumpToHost() {
        guard let target = jumpTarget(for: currentRequest) else { return }
        let cwd = currentRequest?.cwd ?? ""

        if AppDelegate.folderTargetingEditors.contains(target.bundle), !cwd.isEmpty,
           FileManager.default.fileExists(atPath: cwd) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-b", target.bundle, cwd]
            try? task.run()
            return
        }

        // Terminals and everything else: just bring the app forward. Already
        // running is the normal case (it is running this session, after all);
        // `open -b` is the cold-start fallback.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundle).first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            return
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", target.bundle]
        try? task.run()
    }
}
