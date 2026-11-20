//! §9 actions — all manual, confirmed, and reversible-or-harmless. No
//! timer-driven cleanup; the CLI is responsible for confirmation before
//! calling `execute`, and for never offering a bulk "kill all" shortcut.

use std::time::Duration;

use crate::error::VitalsError;
use crate::probes::shell;

/// `ddev start`/`stop`/`poweroff` talk to Docker per container and
/// routinely take longer than the 10 s default — a stop that is killed
/// half-way leaves the project in a worse state than not stopping it.
const DDEV_TIMEOUT: Duration = Duration::from_secs(180);
/// How long `restart_app` waits for the app to finish quitting.
const QUIT_WAIT: Duration = Duration::from_secs(30);

/// Every name `vitals --fix <name>` accepts — the single source of truth
/// shared by the CLI's parser error message and the rules' contract test,
/// so a rule can never again advertise an action that doesn't exist.
pub const ACTION_NAMES: &[&str] = &[
    "poweroff",
    "stop_project",
    "stop_backup",
    "add_exclusions",
    "kill_orphaned_agents",
    "kill_runaway_processes",
    "kill_session",
    "prune_docker_images",
    "start_project",
    "quit_app",
    "restart_app",
    "free_idle",
];

#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Poweroff,
    StopProject(String),
    StopBackup,
    AddExclusions(Vec<String>),
    KillOrphanedAgents(Vec<u32>),
    KillRunawayProcesses(Vec<u32>),
    KillSession(u32),
    /// Deliberately the conservative, non-`-a` prune: only removes
    /// dangling (untagged) images no container still references, never
    /// tagged-but-unused ones. Matches what `probes::docker::
    /// dangling_images` actually measures, so the reclaimable figure a
    /// finding reports and what this action frees stay honest.
    PruneDockerImages,
    StartProject(String),
    /// Asks the app to quit the normal way (AppleScript `quit`), so it can
    /// save state and ask about unsaved work itself.
    QuitApp(String),
    /// `QuitApp`, wait until its processes are gone, then reopen it.
    RestartApp(String),
    /// Several actions in order — multiple `--target`s, or `free_idle`.
    /// Every step runs even if an earlier one fails; the first error is
    /// reported afterwards.
    Batch(Vec<Action>),
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
            Action::KillRunawayProcesses(pids) => format!("kill {}", join_pids(pids)),
            Action::KillSession(pid) => format!("kill {pid}"),
            Action::PruneDockerImages => "docker image prune -f".to_string(),
            Action::StartProject(name) => format!("ddev start {name}"),
            Action::QuitApp(name) => format!("osascript -e 'quit app \"{name}\"'"),
            Action::RestartApp(name) => {
                format!("osascript -e 'quit app \"{name}\"' && open -a \"{name}\"")
            }
            Action::Batch(actions) => actions
                .iter()
                .map(Action::describe)
                .collect::<Vec<_>>()
                .join("; "),
        }
    }

    /// App names end up inside an AppleScript string literal and as an
    /// argument to `open -a`. Anything that could close the literal, read
    /// as an option, or is not plausibly a name is refused, not escaped.
    pub fn validate_app_name(name: &str) -> Result<(), String> {
        let plausible = !name.is_empty()
            && name.len() <= 100
            && !name.starts_with('-')
            && !name.contains(['"', '\\', '\'', '/'])
            && !name.chars().any(char::is_control);
        if plausible {
            Ok(())
        } else {
            Err(format!("`{name}` is not a valid app name"))
        }
    }

    /// DDEV project names are hostnames. Enforcing that here keeps a
    /// target like `--remove-data` from ever reaching `ddev stop` as a
    /// flag — that one would delete the project's database.
    pub fn validate_project_name(name: &str) -> Result<(), String> {
        let valid = name.len() <= 100
            && name
                .chars()
                .next()
                .is_some_and(|c| c.is_ascii_alphanumeric())
            && name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '.' | '_'));
        if valid {
            Ok(())
        } else {
            Err(format!("`{name}` is not a valid DDEV project name"))
        }
    }

    /// PID 0 addresses the caller's whole process group and PID 1 is
    /// `launchd`; neither is ever a legitimate target.
    pub fn validate_pid(pid: u32) -> Result<(), String> {
        if pid <= 1 || pid == std::process::id() {
            return Err(format!("refusing to signal pid {pid}"));
        }
        Ok(())
    }

    /// Checks everything this action is about to hand to another program.
    /// `execute` calls it first, so no caller can skip it.
    pub fn validate(&self) -> Result<(), String> {
        match self {
            Action::StopProject(name) | Action::StartProject(name) => {
                Self::validate_project_name(name)
            }
            Action::QuitApp(name) | Action::RestartApp(name) => Self::validate_app_name(name),
            Action::KillSession(pid) => Self::validate_pid(*pid),
            Action::KillOrphanedAgents(pids) | Action::KillRunawayProcesses(pids) => {
                pids.iter().try_for_each(|pid| Self::validate_pid(*pid))
            }
            Action::AddExclusions(paths) => paths.iter().try_for_each(|path| {
                if path.is_empty() || path.starts_with('-') {
                    Err(format!("`{path}` is not a valid path"))
                } else {
                    Ok(())
                }
            }),
            Action::Batch(actions) => actions.iter().try_for_each(Action::validate),
            Action::Poweroff | Action::StopBackup | Action::PruneDockerImages => Ok(()),
        }
    }

    pub fn execute(&self) -> Result<(), VitalsError> {
        self.validate().map_err(refused)?;
        match self {
            Action::Poweroff => {
                shell::run_with_timeout("ddev", &["poweroff"], DDEV_TIMEOUT).map(drop)
            }
            Action::StopProject(name) => {
                shell::run_with_timeout("ddev", &["stop", name], DDEV_TIMEOUT).map(drop)
            }
            Action::StartProject(name) => {
                shell::run_with_timeout("ddev", &["start", name], DDEV_TIMEOUT).map(drop)
            }
            Action::QuitApp(name) => quit_app(name),
            Action::RestartApp(name) => {
                quit_app(name)?;
                wait_until_quit(name);
                shell::run("open", &["-a", name]).map(drop)
            }
            Action::Batch(actions) => {
                let mut first_error = None;
                for action in actions {
                    if let Err(err) = action.execute() {
                        first_error.get_or_insert(err);
                    }
                }
                first_error.map_or(Ok(()), Err)
            }
            Action::StopBackup => shell::run("tmutil", &["stopbackup"]).map(drop),
            Action::AddExclusions(paths) => {
                // No shell is involved, so `~` has to be expanded here;
                // `tmutil` would otherwise look for a folder named `~`.
                let expanded: Vec<String> = paths
                    .iter()
                    .map(|path| crate::probes::time_machine::expand_tilde(path))
                    .collect();
                let mut args = vec!["addexclusion"];
                args.extend(expanded.iter().map(String::as_str));
                shell::run("tmutil", &args).map(drop)
            }
            Action::KillOrphanedAgents(pids) => pids
                .iter()
                .try_for_each(|&pid| terminate_with_escalation(pid)),
            Action::KillRunawayProcesses(pids) => pids
                .iter()
                .try_for_each(|&pid| terminate_with_escalation(pid)),
            Action::KillSession(pid) => {
                ensure_agent_process(*pid)?;
                terminate_with_escalation(*pid)
            }
            Action::PruneDockerImages => shell::run("docker", &["image", "prune", "-f"]).map(drop),
        }
    }
}

fn refused(reason: String) -> VitalsError {
    VitalsError::CommandExitedWithError {
        command: "vitals --fix".to_string(),
        stderr: reason,
    }
}

/// `kill_session` is for Claude Code sessions and IDE agents only. A PID
/// from an earlier report may meanwhile belong to something else (the
/// process exited and the number was reused), so the process is looked
/// up again right before it is signalled.
fn ensure_agent_process(pid: u32) -> Result<(), VitalsError> {
    // Two calls, as in `probes::processes`: with both columns in one,
    // `ps` pads and cuts the first to a fixed width.
    let pid_arg = pid.to_string();
    let gone = |_| refused(format!("pid {pid} is no longer running"));
    let comm = shell::run("ps", &["-p", &pid_arg, "-o", "comm="]).map_err(gone)?;
    let command = shell::run("ps", &["-p", &pid_arg, "-o", "command="]).map_err(gone)?;
    if is_agent_command(&comm, &command) {
        Ok(())
    } else {
        Err(refused(format!(
            "pid {pid} is not a Claude Code session or IDE agent"
        )))
    }
}

/// Sessions show the bare executable name `claude` (or a path ending in
/// it); agents carry `/acp-agents/` in their command line.
fn is_agent_command(comm: &str, command: &str) -> bool {
    comm.trim().rsplit('/').next() == Some("claude") || command.contains("/acp-agents/")
}

/// Escapes every character that has a meaning in a regular expression.
fn regex_literal(text: &str) -> String {
    text.chars()
        .flat_map(|c| {
            let special = "\\.^$|?*+()[]{}".contains(c);
            special
                .then_some('\\')
                .into_iter()
                .chain(std::iter::once(c))
        })
        .collect()
}

fn quit_app(name: &str) -> Result<(), VitalsError> {
    let script = format!("quit app \"{name}\"");
    shell::run_with_timeout("osascript", &["-e", &script], QUIT_WAIT).map(drop)
}

/// `pgrep -f` exits non-zero once nothing matches any more. The name is
/// matched literally: `pgrep` takes a regular expression, so every
/// character that means something there is escaped first.
fn wait_until_quit(name: &str) {
    let pattern = format!("/{}\\.app/", regex_literal(name));
    let start = std::time::Instant::now();
    while start.elapsed() < QUIT_WAIT && shell::run("pgrep", &["-f", &pattern]).is_ok() {
        std::thread::sleep(Duration::from_millis(500));
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
    fn describes_kill_runaway_processes_with_all_pids() {
        let action = Action::KillRunawayProcesses(vec![4242, 4243]);
        assert_eq!(action.describe(), "kill 4242 4243");
    }

    #[test]
    fn describes_kill_session_with_single_pid() {
        assert_eq!(Action::KillSession(90548).describe(), "kill 90548");
    }

    #[test]
    fn describes_start_quit_restart_and_batches() {
        assert_eq!(
            Action::StartProject("witte".into()).describe(),
            "ddev start witte"
        );
        assert_eq!(
            Action::QuitApp("Google Chrome".into()).describe(),
            "osascript -e 'quit app \"Google Chrome\"'"
        );
        assert!(Action::RestartApp("PhpStorm".into())
            .describe()
            .ends_with("open -a \"PhpStorm\""));
        let batch = Action::Batch(vec![
            Action::StopProject("a".into()),
            Action::KillSession(7),
        ]);
        assert_eq!(batch.describe(), "ddev stop a; kill 7");
    }

    #[test]
    fn refuses_app_names_that_could_break_out_of_the_script() {
        assert!(Action::validate_app_name("Google Chrome").is_ok());
        assert!(Action::validate_app_name("x\" & do shell script \"rm").is_err());
        assert!(Action::validate_app_name("").is_err());
        assert!(Action::validate_app_name("-g").is_err());
        assert!(Action::validate_app_name("../../bin/sh").is_err());
        assert!(Action::validate_app_name("a\nb").is_err());
    }

    /// `ddev stop --remove-data` deletes the database; a target must
    /// never be able to turn into that.
    #[test]
    fn refuses_project_names_that_could_be_read_as_flags() {
        assert!(Action::validate_project_name("typo3-pagetree_facets.v13").is_ok());
        assert!(Action::validate_project_name("--remove-data").is_err());
        assert!(Action::validate_project_name("-a").is_err());
        assert!(Action::validate_project_name("a b").is_err());
        assert!(Action::validate_project_name("").is_err());
        let err = Action::StopProject("--remove-data".into())
            .execute()
            .unwrap_err();
        assert!(err.to_string().contains("not a valid DDEV project name"));
    }

    #[test]
    fn refuses_to_signal_process_groups_launchd_or_itself() {
        assert!(Action::validate_pid(0).is_err());
        assert!(Action::validate_pid(1).is_err());
        assert!(Action::validate_pid(std::process::id()).is_err());
        assert!(Action::validate_pid(90548).is_ok());
        assert!(Action::KillOrphanedAgents(vec![4242, 0])
            .validate()
            .is_err());
        assert!(Action::Batch(vec![Action::KillSession(1)])
            .validate()
            .is_err());
    }

    #[test]
    fn exclusion_paths_cannot_be_options() {
        assert!(Action::AddExclusions(vec!["~/.orbstack".into()])
            .validate()
            .is_ok());
        assert!(Action::AddExclusions(vec!["-p".into()]).validate().is_err());
    }

    #[test]
    fn kill_session_only_accepts_claude_sessions_and_ide_agents() {
        assert!(is_agent_command("claude\n", "claude\n"));
        assert!(is_agent_command(
            "/Users/km/.local/bin/claude",
            "claude --continue"
        ));
        assert!(is_agent_command(
            "node",
            "node /Users/km/Library/Caches/JetBrains/PhpStorm2026.2/acp-agents/claude-acp/bin"
        ));
        assert!(!is_agent_command(
            "/Applications/Slack.app/Contents/MacOS/Slack",
            "/Applications/Slack.app/Contents/MacOS/Slack"
        ));
        assert!(!is_agent_command("/usr/bin/ssh", "ssh claude@host"));
        assert!(!is_agent_command("", ""));
    }

    #[test]
    fn app_names_are_matched_literally_when_waiting_for_them_to_quit() {
        assert_eq!(regex_literal("Visual Studio Code"), "Visual Studio Code");
        assert_eq!(regex_literal("C++ (beta).app"), "C\\+\\+ \\(beta\\)\\.app");
    }

    #[test]
    fn batch_runs_every_step_and_reports_the_first_failure() {
        let batch = Action::Batch(vec![
            Action::QuitApp("bad\"name".into()),
            Action::QuitApp("also\\bad".into()),
        ]);
        let err = batch.execute().unwrap_err();
        assert!(err.to_string().contains("bad\"name"));
    }

    #[test]
    fn describes_prune_docker_images() {
        assert_eq!(
            Action::PruneDockerImages.describe(),
            "docker image prune -f"
        );
    }
}
