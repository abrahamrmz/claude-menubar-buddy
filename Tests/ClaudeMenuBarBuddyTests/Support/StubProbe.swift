import BuddyCore

struct StubProbe: FileProbe {
    var dirs: Set<String> = ["/"]
    var files: Set<String> = []
    var gitRoots: [String] = []
    func resolvedDirectory(_ p: String) -> String? { dirs.contains(p) ? p : nil }
    func exists(_ p: String) -> Bool { files.contains(p) || dirs.contains(p) }
    func isDirectory(_ p: String) -> Bool { dirs.contains(p) }
    func isInsideGitWorkTree(_ p: String) -> Bool { gitRoots.contains { p == $0 || p.hasPrefix($0 + "/") } }
}
