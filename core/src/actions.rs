//! §9 actions — all manual, confirmed, and reversible-or-harmless. No
//! timer-driven cleanup; the CLI is responsible for confirmation before
//! calling `execute`, and for never offering a bulk "kill all" shortcut.

use crate::error::VitalsError;
use crate::probes::shell;

#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Poweroff,
    StopProject(String),
    StopBackup,
    AddExclusions(Vec<String>),
    KillOrphanedAgents(Vec<u32>),
    KillSession(u32),
    /// Deliberately the conservative, non-`-a` prune: only removes
    /// dangling (untagged) images no container still references, never
    /// tagged-but-unused ones. Matches what `probes::docker::
    /// dangling_images` actually measures, so the reclaimable figure a
    /// finding reports and what this action frees stay honest.
    PruneDockerImages,
}

impl Action {
    /// Human-readable preview of the command this action will run —
    /// what `--dry-run` prints instead of executing.
    pub fn describe(&self) -> String {
        match self {
            Action::Poweroff => "ddev poweroff".to_string(),
            Action::StopProject(name) => format!("ddev stop {name}"),
            Action::StopBackup => "tmutil stopbackup".to_string(),
            Action::AddExclusions(paths) => format!("tmutil addexclusion {}", paths.join(" ")),
            Action::KillOrphanedAgents(pids) => format!("kill {}", join_pids(pids)),
            Action::KillSession(pid) => format!("kill {pid}"),
            Action::PruneDockerImages => "docker image prune -f".to_string(),
        }
    }

    pub fn execute(&self) -> Result<(), VitalsError> {
        match self {
            Action::Poweroff => shell::run("ddev", &["poweroff"]).map(drop),
            Action::StopProject(name) => shell::run("ddev", &["stop", name]).map(drop),
            Action::StopBackup => shell::run("tmutil", &["stopbackup"]).map(drop),
            Action::AddExclusions(paths) => {
                let mut args = vec!["addexclusion"];
                args.extend(paths.iter().map(String::as_str));
                shell::run("tmutil", &args).map(drop)
            }
            Action::KillOrphanedAgents(pids) => pids
                .iter()
                .try_for_each(|&pid| terminate_with_escalation(pid)),
            Action::KillSession(pid) => terminate_with_escalation(*pid),
            Action::PruneDockerImages => shell::run("docker", &["image", "prune", "-f"]).map(drop),
        }
    }
}

fn join_pids(pids: &[u32]) -> String {
    pids.iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(" ")
}

fn is_alive(pid: u32) -> bool {
    shell::run("kill", &["-0", &pid.to_string()]).is_ok()
}

/// Sends `SIGTERM`, waits a grace period, then escalates to `SIGKILL` only
/// if the process is still alive (§9: "TERM then KILL after grace").
fn terminate_with_escalation(pid: u32) -> Result<(), VitalsError> {
    shell::run("kill", &["-TERM", &pid.to_string()]).map(drop)?;
    std::thread::sleep(std::time::Duration::from_secs(2));
    if is_alive(pid) {
        shell::run("kill", &["-KILL", &pid.to_string()]).map(drop)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn describes_poweroff() {
        assert_eq!(Action::Poweroff.describe(), "ddev poweroff");
    }

    #[test]
    fn describes_stop_project_with_name() {
        assert_eq!(
            Action::StopProject("witte".to_string()).describe(),
            "ddev stop witte"
        );
    }

    #[test]
    fn describes_stop_backup() {
        assert_eq!(Action::StopBackup.describe(), "tmutil stopbackup");
    }

    #[test]
    fn describes_add_exclusions_with_all_paths() {
        let action = Action::AddExclusions(vec!["~/.orbstack".to_string(), "~/.ddev".to_string()]);
        assert_eq!(action.describe(), "tmutil addexclusion ~/.orbstack ~/.ddev");
    }

    #[test]
    fn describes_kill_orphaned_agents_with_all_pids() {
        let action = Action::KillOrphanedAgents(vec![98823, 98824]);
        assert_eq!(action.describe(), "kill 98823 98824");
    }

    #[test]
    fn describes_kill_session_with_single_pid() {
        assert_eq!(Action::KillSession(90548).describe(), "kill 90548");
    }

    #[test]
    fn describes_prune_docker_images() {
        assert_eq!(
            Action::PruneDockerImages.describe(),
            "docker image prune -f"
        );
    }
}
