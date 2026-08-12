//! Buckets raw `probes::processes::ProcessEntry` rows into the process
//! kinds the JSON contract cares about. Claude sessions match on `comm`
//! (the resolved executable path) per §7 — never on argv or basename,
//! since Claude Code sets argv to plain `claude`. ACP agents are the
//! opposite case: see the doc comment on `acp_agents` for why `command`
//! is the reliable field there instead.

use crate::probes::processes::ProcessEntry;
use crate::types::{AcpAgent, ClaudeSession};

pub fn claude_sessions(processes: &[ProcessEntry]) -> Vec<ClaudeSession> {
    processes
        .iter()
        .filter_map(|process| {
            let (_, after) = process.comm.split_once("/.local/share/claude/versions/")?;
            let version = after.split('/').next()?;

            Some(ClaudeSession {
                pid: process.pid,
                etime_seconds: process.etime_seconds,
                cpu_percent: process.cpu_percent,
                rss_bytes: process.rss_bytes,
                kind: "cli".to_string(),
                version: version.to_string(),
            })
        })
        .collect()
}

/// Unlike the compiled Claude CLI binary, ACP agents run as `node <script>`
/// — an interpreted process whose `comm` is just the generic interpreter
/// name (`node`), not the script path. The identifying path only survives
/// in `command` (full argv), so this matches there instead — the opposite
/// of the CLI-session rule above, and deliberately so (see the "identifies
/// agent by command" test for why `comm` can't be trusted here).
///
/// The same tree also hosts the various MCP tool subprocesses the agent
/// spawns (`playwright-mcp`, `context7-mcp`, a `chrome-devtools-mcp`
/// watchdog, ...), all living under `.../acp-agents/.runtimes/...` — those
/// are tools the agent uses, not the agent itself, and are excluded.
pub fn acp_agents(processes: &[ProcessEntry], retired_versions: &[String]) -> Vec<AcpAgent> {
    processes
        .iter()
        .filter_map(|process| {
            let (before, after) = process.command.split_once("/acp-agents/")?;
            if after.starts_with(".runtimes/") {
                return None;
            }
            let ide_version = before.rsplit('/').next()?;
            if !ide_version.starts_with("PhpStorm") {
                return None;
            }

            Some(AcpAgent {
                pid: process.pid,
                etime_seconds: process.etime_seconds,
                ide_version: ide_version.to_string(),
                orphaned: retired_versions.iter().any(|v| v == ide_version),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn process(comm: &str) -> ProcessEntry {
        process_with(comm, comm)
    }

    fn process_with(comm: &str, command: &str) -> ProcessEntry {
        ProcessEntry {
            pid: 1,
            ppid: 0,
            etime_seconds: 30,
            cpu_percent: 2.1,
            rss_bytes: 151_945_216,
            comm: comm.to_string(),
            command: command.to_string(),
        }
    }

    #[test]
    fn identifies_cli_session_by_versions_path() {
        let processes = vec![process("/Users/km/.local/share/claude/versions/2.1.228")];
        let sessions = claude_sessions(&processes);
        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].version, "2.1.228");
        assert_eq!(sessions[0].kind, "cli");
    }

    #[test]
    fn ignores_daemon_process() {
        let processes = vec![process("/Users/km/.local/bin/claude")];
        assert!(claude_sessions(&processes).is_empty());
    }

    #[test]
    fn ignores_desktop_app_helper() {
        let processes = vec![process(
            "/Applications/Claude.app/Contents/MacOS/Claude Helper",
        )];
        assert!(claude_sessions(&processes).is_empty());
    }

    #[test]
    fn identifies_acp_agent_and_flags_retired_version_as_orphaned() {
        let processes = vec![process(
            "/Users/km/Library/Application Support/JetBrains/PhpStorm2026.1/acp-agents/agent",
        )];
        let retired = vec!["PhpStorm2026.1".to_string()];
        let agents = acp_agents(&processes, &retired);
        assert_eq!(agents.len(), 1);
        assert_eq!(agents[0].ide_version, "PhpStorm2026.1");
        assert!(agents[0].orphaned);
    }

    #[test]
    fn acp_agent_on_active_version_is_not_orphaned() {
        let processes = vec![process(
            "/Users/km/Library/Application Support/JetBrains/PhpStorm2026.2/acp-agents/agent",
        )];
        let agents = acp_agents(&processes, &[]);
        assert!(!agents[0].orphaned);
    }

    #[test]
    fn ignores_non_phpstorm_acp_lookalikes() {
        let processes = vec![process("/opt/homebrew/bin/acp-agents/agent")];
        assert!(acp_agents(&processes, &[]).is_empty());
    }

    /// Real bug found on a live machine: `claude-agent-acp` (the actual ACP
    /// agent) runs as `node <script>`, so its `comm` is the generic
    /// interpreter name `node` — the identifying path only appears in the
    /// full `command`. Matching on `comm` for an interpreted process, unlike
    /// for the compiled Claude CLI binary, misses the real agent entirely.
    #[test]
    fn identifies_agent_by_command_when_comm_is_just_the_interpreter() {
        let processes = vec![process_with(
            "node",
            "node /Users/km/Library/Caches/JetBrains/PhpStorm2026.2/acp-agents/claude-acp/0.24.2/node_modules/.bin/claude-agent-acp --hide-claude-auth",
        )];
        let agents = acp_agents(&processes, &[]);
        assert_eq!(agents.len(), 1);
        assert_eq!(agents[0].ide_version, "PhpStorm2026.2");
    }

    /// Real false positive found on the same machine: MCP tool subprocesses
    /// spawned by the agent (playwright-mcp, context7-mcp, a
    /// chrome-devtools-mcp watchdog, ...) all run from within the same
    /// `.../acp-agents/.runtimes/...` cache tree and would otherwise match
    /// too — they are tools the agent uses, not the agent itself, and must
    /// not be counted (or killed) as one.
    #[test]
    fn ignores_bundled_runtime_tool_subprocesses() {
        let processes = vec![
            process_with(
                "node",
                "node /Users/km/Library/Caches/JetBrains/PhpStorm2026.2/acp-agents/.runtimes/node/24.13.0/npm-cache/_npx/abc/node_modules/.bin/playwright-mcp",
            ),
            process_with(
                "/Users/km/Library/Caches/JetBrains/PhpStorm2026.2/acp-agents/.runtimes/node/24.13.0/bin/node",
                "/Users/km/Library/Caches/JetBrains/PhpStorm2026.2/acp-agents/.runtimes/node/24.13.0/bin/node /Users/km/.../chrome-devtools-mcp/build/src/telemetry/watchdog/main.js",
            ),
        ];
        assert!(acp_agents(&processes, &[]).is_empty());
    }
}
