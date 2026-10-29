import Foundation

/// The command names the general rule knows by heart. Everything else is
/// unknown, which means a card — the safe side.
enum CommandCatalog {
    static let read: Set<String> = [
        "grep", "egrep", "fgrep", "rg", "ag", "ack", "cat", "bat", "head", "tail",
        "wc", "ls", "tree", "stat", "file", "du", "df", "which", "whereis", "type", "pwd", "echo",
        "printf", "date", "basename", "dirname", "realpath", "readlink", "nl", "column", "od", "xxd",
        "hexdump", "strings", "md5", "md5sum", "shasum", "sha256sum", "cksum", "diff", "cmp", "comm",
        "cut", "sort", "uniq", "tr", "fold", "paste", "join", "tac", "rev", "seq", "expand", "unexpand",
        "fmt", "jq", "yq", "pgrep", "ps", "lsof", "id", "whoami", "groups", "uname", "sw_vers",
        "hostname", "uptime", "sleep", "true", "false", "test", "[", "[[", "cd", "pushd", "popd",
        "export", "unset", "set", "shopt", "local", "declare", "typeset", "readonly", "read", "wait",
        "printenv", "tldr", "help", "mdfind", "mdls", "locate", "pbcopy", "pbpaste",
    ]

    static let execute: Set<String> = [
        "bash", "sh", "zsh", "fish", "dash", "ksh", "csh", "tcsh", "source", ".",
        "pip", "pip3", "pipx", "uv", "uvx", "poetry", "pdm", "hatch", "pytest", "py.test", "tox", "nox",
        "node", "nodejs", "npm", "npx", "pnpm", "pnpx", "yarn", "bun", "bunx", "deno", "ruby", "gem",
        "bundle", "rake", "irb", "perl", "php", "composer", "java", "javac", "kotlin", "go", "cargo",
        "rustc", "rustup", "make", "gmake", "cmake", "ninja", "swift", "swiftc", "xcodebuild", "xcrun",
        "clang", "clang++", "gcc", "g++", "cc", "ld", "lldb", "gdb", "docker", "docker-compose", "podman",
        "kubectl", "helm", "terraform", "celery", "gunicorn", "uvicorn", "flask", "django-admin",
        "redis-server", "redis-cli", "psql", "pg_ctl", "pg_dump", "createdb", "dropdb", "mysql",
        "mysqldump", "mongo", "mongosh", "sqlite3", "brew", "port", "mas", "osascript", "open",
        "launchctl", "crontab", "at", "batch", "shortcuts", "automator", "eval", "exec", "su",
        "tccutil", "security", "codesign", "spctl", "csrutil", "nvram", "diskutil", "hdiutil", "pmset",
        "systemsetup", "networksetup", "scutil", "softwareupdate", "installer", "pkgutil",
    ]

    static let external: Set<String> = [
        "curl", "wget", "http", "https", "httpie", "scp", "rsync", "sftp", "ftp", "tftp", "nc", "ncat",
        "netcat", "socat", "telnet", "ping", "ping6", "dig", "nslookup", "host", "traceroute", "mtr",
        "aws", "gcloud", "gsutil", "az", "firebase", "vercel", "netlify", "fly", "flyctl", "heroku",
        "wrangler", "supabase", "railway", "doctl", "s3cmd", "rclone",
    ]

    static let irreversible: Set<String> = [
        "rm", "rmdir", "unlink", "shred", "srm", "truncate", "dd", "kill", "pkill", "killall",
    ]

    static let localChange: Set<String> = [
        "mkdir", "touch", "cp", "mv", "ln", "install", "tee", "chmod", "chown", "chgrp",
        "gunzip", "gzip", "zip", "bunzip2", "xz",
    ]

    static let systemBinDirs: Set<String> = [
        "/bin", "/usr/bin", "/usr/local/bin", "/opt/homebrew/bin", "/sbin", "/usr/sbin",
    ]

    /// `python`, `python3`, `python3.12`… every spelling is the same promise.
    static func isPython(_ name: String) -> Bool {
        name.range(of: "^python[0-9.]*$", options: .regularExpression) != nil
    }
}
