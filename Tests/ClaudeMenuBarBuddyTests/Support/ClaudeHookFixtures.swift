/// Hook payloads captured live from Claude Code 2.1.318 on 2026-11-08, sanitized
/// (user, paths and ids replaced).
enum ClaudeHookFixtures {
    /// PreToolUse inside a subagent: the parent's session_id, plus agent_id and agent_type.
    static let preToolUseSubagent = #"{"session_id":"e575efb6-a7ad-4a1e-ab95-e32b6755393f","transcript_path":"/Users/u/.claude/projects/-tmp-p/e575efb6-a7ad-4a1e-ab95-e32b6755393f.jsonl","cwd":"/tmp/p","scratchpad_dir":"/tmp/claude/scratchpad","prompt_id":"5c1d0f8e-0d7a-4a52-9a43-3f1e5b2d6c71","permission_mode":"default","effort":"medium","agent_id":"ae1aa20fb0eae25fc","agent_type":"general-purpose","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo hijo","description":"Imprime hijo"},"tool_use_id":"toolu_01AbCdEfGhIjKlMnOpQrStUv"}"#

    static let sessionEnd = #"{"session_id":"d1538fa3-1006-4201-924b-8dafae43ffe3","transcript_path":"/Users/u/.claude/projects/-tmp-p/d1538fa3-1006-4201-924b-8dafae43ffe3.jsonl","cwd":"/tmp/p","scratchpad_dir":"/tmp/claude/scratchpad","prompt_id":"29bb5ee2-7537-4c34-a74b-9ace5a1a85f8","hook_event_name":"SessionEnd","reason":"other"}"#
}
