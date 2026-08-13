//! Confirms a `comm == "claude"` candidate (see
//! `classify::claude_session_candidates`) is genuinely the compiled
//! Claude CLI and not a PhpStorm ACP agent's Node process, which sets the
//! same display title. Neither `ps -o comm=` nor `-o command=` exposes
//! the version on this installation layout (a fixed `.app` bundle path,
//! no per-version directory) — but `lsof -p <pid>`'s COMMAND column
//! reports the version number directly for the real binary, and reports
//! the interpreter name (`node`) for a disguised ACP agent, so the same
//! probe both confirms the session and extracts identifying info. The
//! working directory (lsof's `cwd` row) tells sessions running the same
//! version apart by project — version alone doesn't, since a version is
//! typically shared by every session on the machine.
use crate::probes::shell;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClaudeCliInfo {
    pub version: String,
    pub working_directory: Option<String>,
}

/// `None` covers both "not the real CLI" and "the process is already
/// gone" (a race between the process snapshot and this lookup) — neither
/// should abort report collection, so this never returns an error.
pub fn resolve(pid: u32) -> Option<ClaudeCliInfo> {
    let raw = shell::run("lsof", &["-p", &pid.to_string()]).ok()?;
    parse(&raw)
}

fn parse(raw: &str) -> Option<ClaudeCliInfo> {
    let version = raw
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .find(|field| is_semver(field))?;

    // The path is taken as the last whitespace-separated token, so a
    // working directory containing spaces would be truncated to its
    // final segment — an accepted limitation of lsof's column output,
    // matching how other probes in this codebase parse plain-text tool
    // output rather than a machine-readable format.
    let working_directory = raw
        .lines()
        .find(|line| line.split_whitespace().nth(3) == Some("cwd"))
        .and_then(|line| line.split_whitespace().last())
        .map(str::to_string);

    Some(ClaudeCliInfo {
        version: version.to_string(),
        working_directory,
    })
}

fn is_semver(field: &str) -> bool {
    let parts: Vec<&str> = field.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
}

#[cfg(test)]
mod tests {
    use super::*;

    const REAL_SESSION: &str = "COMMAND   PID     USER   FD   TYPE DEVICE  SIZE/OFF     NODE NAME\n\
        2.1.228 40078 km       cwd    DIR    1,15      1696   19872373 /Users/km/Sites/Projects/verdi\n\
        2.1.228 40078 km       txt    REG    1,15 289298144 316524854 /Users/km/.local/share/claude/ClaudeCode.app/Contents/MacOS/claude\n";

    #[test]
    fn extracts_version_from_the_real_binarys_command_field() {
        assert_eq!(parse(REAL_SESSION).unwrap().version, "2.1.228");
    }

    #[test]
    fn extracts_working_directory_from_the_cwd_row() {
        assert_eq!(
            parse(REAL_SESSION).unwrap().working_directory,
            Some("/Users/km/Sites/Projects/verdi".to_string())
        );
    }

    #[test]
    fn working_directory_is_none_when_lsof_has_no_cwd_row() {
        let raw = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n\
                   2.1.228 40078 km txt REG 1,15 289298144 316524854 /some/path\n";
        assert_eq!(parse(raw).unwrap().working_directory, None);
    }

    #[test]
    fn returns_none_for_an_acp_agents_disguised_node_process() {
        let raw = "COMMAND PID     USER   FD   TYPE DEVICE  SIZE/OFF     NODE NAME\n\
                   node    3282   km    txt    REG    1,15 117675408 167969373 /Users/km/acp-agents/.runtimes/node/24.13.0/bin/node\n";
        assert_eq!(parse(raw), None);
    }

    #[test]
    fn returns_none_for_empty_output() {
        assert_eq!(parse(""), None);
    }

    #[test]
    fn ignores_a_dotted_field_with_the_wrong_segment_count() {
        let raw = "1.15 40078 km txt REG 1,15 289298144 316524854 /some/path\n";
        assert_eq!(parse(raw), None);
    }
}
