//! Buckets raw `probes::processes::ProcessEntry` rows into the process
//! kinds the JSON contract cares about.

use crate::probes::processes::ProcessEntry;
use crate::types::AcpAgent;

/// Candidates by display name only — real Claude CLI sessions report
/// `comm` as the bare basename `claude` on this installation layout (a
/// fixed `.app` bundle path, not a per-version directory the way an
/// earlier version of this probe assumed), but so does a PhpStorm ACP
/// agent's Node process, which sets the same display title. `comm`
/// alone can't tell the two apart — `probes::claude_cli::resolve_version`
/// confirms and extracts the version for each candidate this returns.
pub fn claude_session_candidates(processes: &[ProcessEntry]) -> Vec<&ProcessEntry> {
    processes
        .iter()
        .filter(|process| process.comm.rsplit('/').next() == Some("claude"))
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

const INTERPRETERS: [&str; 7] = ["node", "bun", "deno", "php", "python", "python3", "ruby"];
const SCRIPT_EXTENSIONS: [&str; 7] = [".js", ".mjs", ".cjs", ".ts", ".php", ".py", ".rb"];

pub(crate) fn basename(token: &str) -> &str {
    token.rsplit('/').next().unwrap_or(token)
}

/// Short display label for a process: program (or script for interpreters)
/// plus up to two bare long flags. Argument values never appear, since argv
/// can carry secrets.
pub fn command_label(command: &str) -> String {
    let mut tokens = command.split_whitespace();
    let Some(first) = tokens.next() else {
        return String::new();
    };
    let mut rest: Vec<&str> = tokens.collect();
    let mut name = basename(first);
    if INTERPRETERS.contains(&name) {
        if let Some(script) = rest.first().filter(|token| !token.starts_with('-')) {
            name = basename(script);
            rest.remove(0);
            for ext in SCRIPT_EXTENSIONS {
                if let Some(stripped) = name.strip_suffix(ext) {
                    name = stripped;
                    break;
                }
            }
        }
    }
    let flags = rest
        .into_iter()
        .filter(|token| token.starts_with("--") && !token.contains(['=', '/']))
        .take(2);
    std::iter::once(name)
        .chain(flags)
        .collect::<Vec<_>>()
        .join(" ")
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

    /// Real behavior verified on a live machine: a genuine terminal
    /// session's `comm` is the bare basename `claude`, not a versioned
    /// path — an earlier version of this probe assumed the latter and
    /// never matched anything on this installation layout.
    #[test]
    fn identifies_candidate_by_bare_comm() {
        let processes = vec![process("claude")];
        assert_eq!(claude_session_candidates(&processes).len(), 1);
    }

    #[test]
    fn identifies_candidate_by_path_ending_in_claude() {
        let processes = vec![process("/Users/km/.local/bin/claude")];
        assert_eq!(claude_session_candidates(&processes).len(), 1);
    }

    #[test]
    fn ignores_desktop_app_helper() {
        let processes = vec![process(
            "/Applications/Claude.app/Contents/MacOS/Claude Helper",
        )];
        assert!(claude_session_candidates(&processes).is_empty());
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

    #[test]
    fn command_label_uses_script_name_for_interpreters() {
        assert_eq!(
            command_label(
                "/opt/homebrew/bin/node /Users/km/Sites/witte/node_modules/.bin/webpack --watch"
            ),
            "webpack --watch"
        );
    }

    #[test]
    fn command_label_uses_basename_for_binaries() {
        assert_eq!(
            command_label("/usr/local/bin/mysqld --datadir=/var/lib/mysql"),
            "mysqld"
        );
    }

    #[test]
    fn command_label_drops_values_and_short_flags() {
        assert_eq!(
            command_label(
                "/usr/bin/mysql -pSECRET --password=hunter2 --batch https://x.io/?token=abc"
            ),
            "mysql --batch"
        );
    }

    #[test]
    fn command_label_keeps_at_most_two_long_flags() {
        assert_eq!(command_label("/bin/tool --a --b --c"), "tool --a --b");
    }
}
