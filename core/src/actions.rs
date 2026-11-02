//! §9 actions — all manual, confirmed, and reversible-or-harmless. No
//! timer-driven cleanup; the CLI is responsible for confirmation before
//! calling `execute`, and for never offering a bulk "kill all" shortcut.

use crate::error::VitalsError;
use crate::probes::processes::ProcessEntry;
use crate::probes::shell;
use crate::{probes, report};
use std::time::Duration;

/// A first start can pull images, and the timeout kills the child, leaving a half started project.
const START_PROJECT_TIMEOUT: Duration = Duration::from_secs(600);

/// Every name `vitals --fix <name>` accepts — the single source of truth
/// shared by the CLI's parser error message and the rules' contract test,
/// so a rule can never again advertise an action that doesn't exist.
pub const ACTION_NAMES: &[&str] = &[
    "poweroff",
    "stop_project",
    "start_project",
    "stop_backup",
    "add_exclusions",
    "kill_orphaned_agents",
    "kill_runaway_processes",
    "kill_process",
    "prune_docker_images",
];

#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Poweroff,
    StopProject(String),
    StartProject(String),
    StopBackup,
    AddExclusions(Vec<String>),
    KillOrphanedAgents(Vec<u32>),
    KillRunawayProcesses(Vec<u32>),
    /// `verify_identity` runs once before this is built (early error before
    /// the prompt) and again inside `execute`, right before the signal.
    KillProcess {
        pid: u32,
        started_at: u64,
    },
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
            Action::StartProject(name) => format!("ddev start {name}"),
            Action::StopBackup => "tmutil stopbackup".to_string(),
            Action::AddExclusions(paths) => format!("tmutil addexclusion {}", paths.join(" ")),
            Action::KillOrphanedAgents(pids) => format!("kill {}", join_pids(pids)),
            Action::KillRunawayProcesses(pids) => format!("kill {}", join_pids(pids)),
            Action::KillProcess { pid, .. } => format!("kill {pid}"),
            Action::PruneDockerImages => "docker image prune -f".to_string(),
        }
    }

    pub fn execute(&self) -> Result<(), VitalsError> {
        match self {
            Action::Poweroff => shell::run("ddev", &["poweroff"]).map(drop),
            Action::StopProject(name) => shell::run("ddev", &["stop", name]).map(drop),
            Action::StartProject(name) => {
                shell::run_with_timeout("ddev", &["start", name], START_PROJECT_TIMEOUT).map(drop)
            }
            Action::StopBackup => shell::run("tmutil", &["stopbackup"]).map(drop),
            Action::AddExclusions(paths) => {
                let mut args = vec!["addexclusion"];
                args.extend(paths.iter().map(String::as_str));
                shell::run("tmutil", &args).map(drop)
            }
            Action::KillOrphanedAgents(pids) => pids
                .iter()
                .try_for_each(|&pid| terminate_with_escalation(pid)),
            Action::KillRunawayProcesses(pids) => pids
                .iter()
                .try_for_each(|&pid| terminate_with_escalation(pid)),
            Action::KillProcess { pid, started_at } => kill_verified(
                *pid,
                *started_at,
                probes::processes::list,
                report::unix_now,
                terminate_with_escalation,
            ),
            Action::PruneDockerImages => shell::run("docker", &["image", "prune", "-f"]).map(drop),
        }
    }
}

/// Start times come from whole-second `etime` values taken at different
/// moments, so equal processes can differ by a second or two.
const IDENTITY_TOLERANCE_SECONDS: u64 = 2;

/// Parses `<pid>@<started_at>` (Unix seconds). PID 1 is refused outright.
pub fn parse_process_target(target: &str) -> Result<(u32, u64), String> {
    let invalid = || format!("`{target}` is not a valid target, expected <pid>@<started_at>");
    let (pid, started_at) = target.split_once('@').ok_or_else(invalid)?;
    let pid: u32 = pid.parse().map_err(|_| invalid())?;
    let started_at: u64 = started_at.parse().map_err(|_| invalid())?;
    if pid <= 1 {
        return Err(format!("refusing to kill PID {pid}"));
    }
    Ok((pid, started_at))
}

/// Guards against PID reuse: the pid must still exist and have the start
/// time the caller saw, within `IDENTITY_TOLERANCE_SECONDS`. Also applies
/// `is_killable`, so no caller can target a protected process.
pub fn verify_identity(
    pid: u32,
    started_at: u64,
    processes: &[ProcessEntry],
    now: u64,
) -> Result<(), String> {
    let entry = processes
        .iter()
        .find(|p| p.pid == pid)
        .ok_or_else(|| format!("process {pid} is no longer running"))?;
    let actual = now.saturating_sub(entry.etime_seconds);
    if actual.abs_diff(started_at) > IDENTITY_TOLERANCE_SECONDS {
        return Err(format!(
            "process {pid} is no longer the one shown, refresh and try again"
        ));
    }
    if !is_killable(entry) {
        return Err(format!("process {pid} cannot be stopped"));
    }
    Ok(())
}

/// The y/N prompt can stay open long enough for the pid to be reused, so the
/// identity check runs again right before the signal.
fn kill_verified(
    pid: u32,
    started_at: u64,
    list: impl FnOnce() -> Result<Vec<ProcessEntry>, VitalsError>,
    now: impl FnOnce() -> u64,
    kill: impl FnOnce(u32) -> Result<(), VitalsError>,
) -> Result<(), VitalsError> {
    let processes = list()?;
    verify_identity(pid, started_at, &processes, now()).map_err(VitalsError::Refused)?;
    kill(pid)
}

/// Never kill launchd, system daemons, vitals itself or whatever launched it
/// (the menubar app or the user's shell).
pub fn is_killable(p: &ProcessEntry) -> bool {
    const SYSTEM_PREFIXES: [&str; 4] = ["/System/", "/usr/sbin/", "/usr/libexec/", "/sbin/"];
    p.pid > 1
        && p.pid != std::process::id()
        && p.pid != std::os::unix::process::parent_id()
        && !SYSTEM_PREFIXES
            .iter()
            .any(|prefix| p.comm.starts_with(prefix))
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
    fn describes_start_project_with_name() {
        assert_eq!(
            Action::StartProject("witte".to_string()).describe(),
            "ddev start witte"
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
    fn describes_kill_runaway_processes_with_all_pids() {
        let action = Action::KillRunawayProcesses(vec![4242, 4243]);
        assert_eq!(action.describe(), "kill 4242 4243");
    }

    #[test]
    fn describes_kill_process_with_single_pid() {
        let action = Action::KillProcess {
            pid: 90548,
            started_at: 999_400,
        };
        assert_eq!(action.describe(), "kill 90548");
    }

    #[test]
    fn parse_process_target_splits_pid_and_start() {
        assert_eq!(parse_process_target("48213@999400"), Ok((48213, 999400)));
    }

    #[test]
    fn parse_process_target_rejects_bare_pid() {
        assert!(parse_process_target("48213").is_err());
    }

    #[test]
    fn parse_process_target_rejects_pid_one() {
        assert!(parse_process_target("1@5").is_err());
    }

    #[test]
    fn parse_process_target_rejects_garbage() {
        assert!(parse_process_target("abc@5").is_err());
        assert!(parse_process_target("5@abc").is_err());
        assert!(parse_process_target("5@6@7").is_err());
    }

    fn entry(pid: u32, etime_seconds: u64) -> ProcessEntry {
        ProcessEntry {
            pid,
            ppid: 1,
            etime_seconds,
            cpu_percent: 0.0,
            rss_bytes: 0,
            comm: "node".to_string(),
            command: "node server.js".to_string(),
        }
    }

    #[test]
    fn kill_process_refuses_when_start_time_differs() {
        let processes = [entry(48213, 1_000)];
        assert_eq!(
            verify_identity(48213, 999_400, &processes, 1_000_000),
            Err("process 48213 is no longer the one shown, refresh and try again".to_string())
        );
    }

    #[test]
    fn kill_process_accepts_within_tolerance() {
        let processes = [entry(48213, 1_000)];
        assert_eq!(
            verify_identity(48213, 999_002, &processes, 1_000_000),
            Ok(())
        );
        assert_eq!(
            verify_identity(48213, 998_998, &processes, 1_000_000),
            Ok(())
        );
        assert!(verify_identity(48213, 999_003, &processes, 1_000_000).is_err());
        assert!(verify_identity(48213, 998_997, &processes, 1_000_000).is_err());
    }

    #[test]
    fn kill_process_refuses_when_pid_is_gone() {
        let processes = [entry(1234, 1_000)];
        assert_eq!(
            verify_identity(48213, 999_000, &processes, 1_000_000),
            Err("process 48213 is no longer running".to_string())
        );
    }

    fn assert_guarded(pid: u32, comm: &str) {
        let processes = [ProcessEntry {
            comm: comm.to_string(),
            ..entry(pid, 1_000)
        }];
        assert_eq!(
            verify_identity(pid, 999_000, &processes, 1_000_000),
            Err(format!("process {pid} cannot be stopped"))
        );
    }

    #[test]
    fn guard_refuses_launchd_even_when_identity_matches() {
        assert_guarded(1, "/sbin/launchd");
    }

    #[test]
    fn guard_refuses_own_and_parent_process() {
        assert_guarded(std::process::id(), "/usr/local/bin/vitals");
        assert_guarded(std::os::unix::process::parent_id(), "/bin/zsh");
    }

    #[test]
    fn guard_refuses_system_paths() {
        assert_guarded(
            48213,
            "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
        );
        assert_guarded(48214, "/usr/sbin/cfprefsd");
        assert_guarded(48215, "/usr/libexec/trustd");
        assert_guarded(48216, "/sbin/mount");
    }

    #[test]
    fn guard_allows_user_process() {
        assert!(is_killable(&entry(48213, 1_000)));
    }

    fn run_kill(processes: Vec<ProcessEntry>) -> (Result<(), String>, Vec<u32>) {
        let mut killed = Vec::new();
        let result = kill_verified(
            48213,
            999_400,
            || Ok(processes),
            || 1_000_000,
            |pid| {
                killed.push(pid);
                Ok(())
            },
        );
        (result.map_err(|err| err.to_string()), killed)
    }

    #[test]
    fn execute_reverifies_and_skips_a_reused_pid() {
        let (result, killed) = run_kill(vec![entry(48213, 5)]);
        assert_eq!(
            result,
            Err("process 48213 is no longer the one shown, refresh and try again".to_string())
        );
        assert!(killed.is_empty());
    }

    #[test]
    fn execute_skips_a_pid_that_exited_meanwhile() {
        let (result, killed) = run_kill(Vec::new());
        assert_eq!(
            result,
            Err("process 48213 is no longer running".to_string())
        );
        assert!(killed.is_empty());
    }

    #[test]
    fn execute_signals_when_identity_still_matches() {
        let (result, killed) = run_kill(vec![entry(48213, 600)]);
        assert_eq!(result, Ok(()));
        assert_eq!(killed, vec![48213]);
    }

    #[test]
    fn parse_process_target_rejects_pid_zero() {
        assert!(parse_process_target("0@5").is_err());
    }

    #[test]
    fn describes_prune_docker_images() {
        assert_eq!(
            Action::PruneDockerImages.describe(),
            "docker image prune -f"
        );
    }
}
