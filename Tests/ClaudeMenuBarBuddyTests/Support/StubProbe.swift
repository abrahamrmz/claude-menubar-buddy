import BuddyCore

struct StubProbe: FileProbe {
    var dirs: Set<String> = ["/"]
    var files: Set<String> = []
    var gitRoots: [String] = []
    /// Link path → the text stored in the link, exactly as `readlink` gives it.
    var links: [String: String] = [:]
    /// Folder path → what `realpath` answers for it, when that is another spelling.
    var aliases: [String: String] = [:]
    func resolvedDirectory(_ p: String) -> String? { aliases[p] ?? (dirs.contains(p) ? p : nil) }
    func exists(_ p: String) -> Bool { files.contains(p) || dirs.contains(p) }
    func isDirectory(_ p: String) -> Bool { dirs.contains(p) }
    func isInsideGitWorkTree(_ p: String) -> Bool { gitRoots.contains { p == $0 || p.hasPrefix($0 + "/") } }
    func symlinkDestination(_ p: String) -> String? { links[p] }
}
