use std::io::{IsTerminal, Write};
use std::process::ExitCode;

use clap::Parser;
use vitals_core::actions::{parse_process_target, verify_identity, Action};
use vitals_core::config::Config;
use vitals_core::probes::processes::ProcessEntry;
use vitals_core::types::{Finding, Severity, VitalsReport};

/// Vital signs of your local dev stack.
#[derive(Parser)]
#[command(name = "vitals", version, about)]
struct Cli {
    /// Output machine-readable JSON instead of the TTY report
    #[arg(long)]
    json: bool,

    /// Disable colored output
    #[arg(long)]
    no_color: bool,

    /// Apply a remediation action: poweroff, stop_project, start_project,
    /// stop_backup, add_exclusions, kill_orphaned_agents, kill_runaway_processes,
    /// kill_process, prune_docker_images
    #[arg(long, value_name = "ACTION")]
    fix: Option<String>,

    /// Target for actions that need one (a DDEV project name, or `<pid>@<started_at>` for kill_process)
    #[arg(long, value_name = "VALUE")]
    target: Option<String>,

    /// Show what an action would do without executing it
    #[arg(long)]
    dry_run: bool,

    /// Skip the confirmation prompt (e.g. when a caller like the menubar
    /// app already confirmed via its own dialog)
    #[arg(short = 'y', long)]
    yes: bool,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let use_color = !cli.no_color && std::io::stdout().is_terminal();

    let config = match vitals_core::config::load() {
        Ok(config) => config,
        Err(err) => {
            report_error(&err, cli.json, use_color);
            return ExitCode::FAILURE;
        }
    };

    if let Some(action_name) = &cli.fix {
        return run_fix(
            action_name,
            cli.target.as_deref(),
            cli.dry_run,
            cli.yes,
            &config,
            cli.json,
            use_color,
        );
    }

    match vitals_core::report::collect(&config) {
        Ok((mut report, processes)) => {
            report.findings = vitals_core::rules::evaluate(&report, &processes, &config);
            report.verdict = vitals_core::verdict::derive(&report, &processes, &config);
            if cli.json {
                println!(
                    "{}",
                    serde_json::to_string(&report).expect("VitalsReport always serializes")
                );
            } else {
                print!("{}", format_tty(&report, use_color));
            }
            ExitCode::from(exit_code_for(&report.findings))
        }
        Err(err) => {
            report_error(&err, cli.json, use_color);
            ExitCode::FAILURE
        }
    }
}

fn run_fix(
    action_name: &str,
    target: Option<&str>,
    dry_run: bool,
    yes: bool,
    config: &Config,
    json: bool,
    use_color: bool,
) -> ExitCode {
    let needs_process_snapshot =
        action_name == "kill_orphaned_agents" || action_name == "kill_runaway_processes";
    let (report, processes, now) = if action_name == "kill_process" {
        // A bare process list is enough here, and `now` must sit right next to
        // it: a full collect can take seconds and would skew the identity check.
        match vitals_core::probes::processes::list() {
            Ok(processes) => (None, Some(processes), vitals_core::report::unix_now()),
            Err(err) => {
                report_error(&err, json, use_color);
                return ExitCode::FAILURE;
            }
        }
    } else if needs_process_snapshot {
        match vitals_core::report::collect(config) {
            Ok((report, processes)) => (Some(report), Some(processes), 0),
            Err(err) => {
                report_error(&err, json, use_color);
                return ExitCode::FAILURE;
            }
        }
    } else {
        (None, None, 0)
    };

    let action = match build_action(
        action_name,
        target,
        report.as_ref(),
        processes.as_deref(),
        config,
        now,
    ) {
        Ok(action) => action,
        Err(message) => {
            eprintln!("vitals: {message}");
            return ExitCode::FAILURE;
        }
    };

    if dry_run {
        println!("Would run: {}", action.describe());
        return ExitCode::SUCCESS;
    }

    if needs_confirmation(yes, config.actions.require_confirmation) && !confirm(&action) {
        println!("Aborted.");
        return ExitCode::SUCCESS;
    }

    match action.execute() {
        Ok(()) => {
            println!("Done: {}", action.describe());
            ExitCode::SUCCESS
        }
        Err(err) => {
            report_error(&err, json, use_color);
            ExitCode::FAILURE
        }
    }
}

fn needs_confirmation(yes: bool, require_confirmation: bool) -> bool {
    !yes && require_confirmation
}

fn confirm(action: &Action) -> bool {
    print!("Run `{}`? [y/N] ", action.describe());
    let _ = std::io::stdout().flush();
    let mut input = String::new();
    if std::io::stdin().read_line(&mut input).is_err() {
        return false;
    }
    matches!(input.trim().to_lowercase().as_str(), "y" | "yes")
}

/// ddev would read a leading dash as a flag, and `--yes` skips the prompt that would show it.
fn project_name(name: &str) -> Result<&str, String> {
    if name.is_empty() || name.starts_with('-') {
        return Err(format!("`{name}` is not a valid ddev project name"));
    }
    Ok(name)
}

/// Turns the action name and target into an `Action`, failing early with a
/// readable message. `report` is only needed by `kill_orphaned_agents`,
/// `processes` by `kill_runaway_processes` and `kill_process`; every other
/// action should skip the expensive, DDEV-touching `collect()`. `now` is the
/// Unix time taken right after the process list, used only by `kill_process`
/// to verify the target's identity and the kill guard before the prompt.
fn build_action(
    name: &str,
    target: Option<&str>,
    report: Option<&VitalsReport>,
    processes: Option<&[ProcessEntry]>,
    config: &Config,
    now: u64,
) -> Result<Action, String> {
    match name {
        "poweroff" => Ok(Action::Poweroff),
        "stop_backup" => Ok(Action::StopBackup),
        "add_exclusions" => {
            if config.watch.timemachine_exclusions.is_empty() {
                return Err(
                    "no `watch.timemachine_exclusions` configured in ~/.vitals.toml".to_string(),
                );
            }
            Ok(Action::AddExclusions(
                config.watch.timemachine_exclusions.clone(),
            ))
        }
        "kill_orphaned_agents" => {
            let report =
                report.ok_or("internal error: no report collected for kill_orphaned_agents")?;
            let pids: Vec<u32> = report
                .processes
                .acp_agents
                .iter()
                .filter(|agent| agent.orphaned)
                .map(|agent| agent.pid)
                .collect();
            if pids.is_empty() {
                return Err("no orphaned ACP agents found".to_string());
            }
            Ok(Action::KillOrphanedAgents(pids))
        }
        "kill_runaway_processes" => {
            let processes = processes
                .ok_or("internal error: no process list collected for kill_runaway_processes")?;
            let pids: Vec<u32> = processes
                .iter()
                .filter(|process| vitals_core::rules::is_runaway(process, config))
                .map(|process| process.pid)
                .collect();
            if pids.is_empty() {
                return Err("no runaway processes found".to_string());
            }
            Ok(Action::KillRunawayProcesses(pids))
        }
        "stop_project" => {
            let name = target.ok_or("`stop_project` requires --target <project-name>")?;
            Ok(Action::StopProject(project_name(name)?.to_string()))
        }
        "start_project" => {
            let name = target.ok_or("`start_project` requires --target <project-name>")?;
            Ok(Action::StartProject(project_name(name)?.to_string()))
        }
        "kill_process" => {
            let target = target.ok_or("`kill_process` requires --target <pid>@<started_at>")?;
            let processes =
                processes.ok_or("internal error: no process list collected for kill_process")?;
            let (pid, started_at) = parse_process_target(target)?;
            verify_identity(pid, started_at, processes, now)?;
            Ok(Action::KillProcess { pid, started_at })
        }
        "prune_docker_images" => Ok(Action::PruneDockerImages),
        other => Err(format!(
            "unknown action `{other}` (expected one of: {})",
            vitals_core::actions::ACTION_NAMES.join(", ")
        )),
    }
}

fn exit_code_for(findings: &[Finding]) -> u8 {
    match findings.iter().map(|f| f.severity).max() {
        Some(Severity::Critical) => 2,
        Some(Severity::Warn) => 1,
        Some(Severity::Info) | None => 0,
    }
}

fn format_tty(report: &VitalsReport, use_color: bool) -> String {
    let mut out = String::new();
    let system = &report.system;

    out.push_str(&format_verdict(&report.verdict, use_color));
    out.push('\n');
    out.push_str(&format!(
        "load     {:.2} {:.2} {:.2}  ({}P {}E, {} total)\n",
        system.load.m1,
        system.load.m5,
        system.load.m15,
        system.cores.performance,
        system.cores.efficiency,
        system.cores.total,
    ));
    out.push_str(&format!(
        "memory   {:?}, {}% free, {:.1} GB compressed, {} pageouts\n",
        system.memory.pressure_level,
        system.memory.free_percent,
        system.memory.compressor_bytes as f64 / 1024.0 / 1024.0 / 1024.0,
        system.memory.pageouts,
    ));
    out.push_str(&format!(
        "swap     {:.1} GB used\n",
        system.memory.swap_used_bytes as f64 / 1024.0 / 1024.0 / 1024.0,
    ));
    out.push_str(&format!("uptime   {}s\n", system.uptime_seconds));

    out.push_str(&format!(
        "\ntime machine   {}\n",
        if report.time_machine.running {
            format!(
                "running ({})",
                report
                    .time_machine
                    .phase
                    .as_deref()
                    .unwrap_or("unknown phase")
            )
        } else {
            "idle".to_string()
        }
    ));
    out.push_str(&format!(
        "ddev           {} running, {} stopped, {} paused, {} problem(s)\n",
        report.ddev.running.len(),
        report.ddev.stopped_count,
        report.ddev.paused_count,
        report.ddev.problems.len(),
    ));
    let unmanaged_containers = report
        .docker
        .containers
        .iter()
        .filter(|c| !c.ddev_managed)
        .count();
    out.push_str(&format!(
        "docker         {} container(s) ({} unmanaged)\n",
        report.docker.containers.len(),
        unmanaged_containers,
    ));
    out.push_str(&format!(
        "processes      {} claude session(s), {} acp agent(s), orbstack {}\n",
        report.processes.claude_sessions.len(),
        report.processes.acp_agents.len(),
        if report.processes.orbstack.is_some() {
            "running"
        } else {
            "not running"
        },
    ));

    out.push('\n');
    if report.findings.is_empty() {
        out.push_str("No findings — all vital signs normal.\n");
    } else {
        out.push_str("Findings:\n");
        for finding in &report.findings {
            let severity = format!("{:?}", finding.severity).to_lowercase();
            let tag = if use_color {
                match finding.severity {
                    Severity::Critical => format!("\x1b[31m{severity}\x1b[0m"),
                    Severity::Warn => format!("\x1b[33m{severity}\x1b[0m"),
                    Severity::Info => format!("\x1b[36m{severity}\x1b[0m"),
                }
            } else {
                severity
            };
            out.push_str(&format!(
                "  [{tag}] {}: {}\n",
                finding.rule, finding.message
            ));
            if !finding.actions.is_empty() {
                out.push_str(&format!("    actions: {}\n", finding.actions.join(", ")));
            }
        }
    }

    out
}

fn format_verdict(verdict: &vitals_core::verdict::Verdict, use_color: bool) -> String {
    let headline = if use_color {
        let code = match verdict.severity {
            Some(Severity::Critical) => "31",
            Some(Severity::Warn) => "33",
            _ => "32",
        };
        format!("\x1b[1;{code}m{}\x1b[0m", verdict.headline)
    } else {
        verdict.headline.clone()
    };
    if verdict.detail.is_empty() {
        format!("{headline}\n")
    } else {
        format!("{headline}  {}\n", verdict.detail)
    }
}

fn report_error(err: &vitals_core::VitalsError, json: bool, use_color: bool) {
    if json {
        let payload = serde_json::json!({ "schemaVersion": vitals_core::types::SCHEMA_VERSION, "error": err.to_string() });
        println!("{payload}");
    } else if use_color {
        eprintln!("\x1b[31mvitals:\x1b[0m {err}");
    } else {
        eprintln!("vitals: {err}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use vitals_core::config::Config;
    use vitals_core::types::{
        AcpAgent, CoreCount, CpuUsage, DdevInfo, DockerInfo, LoadAverage, MemoryInfo,
        PressureLevel, ProcessesInfo, SystemInfo, TimeMachineInfo,
    };

    #[test]
    fn needs_confirmation_when_config_requires_it_and_yes_not_passed() {
        assert!(needs_confirmation(false, true));
    }

    #[test]
    fn skips_confirmation_when_yes_flag_passed() {
        assert!(!needs_confirmation(true, true));
    }

    #[test]
    fn skips_confirmation_when_config_disables_it() {
        assert!(!needs_confirmation(false, false));
    }

    fn sample_report(findings: Vec<Finding>) -> VitalsReport {
        VitalsReport {
            schema_version: 1,
            timestamp: "2026-08-12T09:52:00Z".to_string(),
            system: SystemInfo {
                uptime_seconds: 1_204_140,
                load: LoadAverage {
                    m1: 3.27,
                    m5: 10.78,
                    m15: 9.82,
                },
                cores: CoreCount {
                    performance: 10,
                    efficiency: 4,
                    total: 14,
                },
                memory: MemoryInfo {
                    pressure_level: PressureLevel::Normal,
                    free_percent: 36,
                    used_percent: 64,
                    page_size_bytes: 16384,
                    compressor_bytes: 10_905_550_848,
                    swap_used_bytes: 21_690_548_224,
                    pageouts: 7_301_205,
                },
                cpu: CpuUsage::default(),
            },
            time_machine: TimeMachineInfo {
                running: false,
                phase: None,
                changed_item_count: None,
                exclusions: Vec::new(),
            },
            ddev: DdevInfo::default(),
            docker: DockerInfo::default(),
            processes: ProcessesInfo::default(),
            findings,
            consumers: Vec::new(),
            verdict: vitals_core::verdict::Verdict::calm(),
        }
    }

    fn finding(rule: &str, severity: Severity) -> Finding {
        Finding {
            rule: rule.to_string(),
            severity,
            message: format!("{rule} fired"),
            actions: vec!["some_action".to_string()],
        }
    }

    #[test]
    fn exit_code_is_zero_with_no_findings() {
        assert_eq!(exit_code_for(&[]), 0);
    }

    #[test]
    fn exit_code_is_zero_with_only_info_findings() {
        assert_eq!(
            exit_code_for(&[finding("uptime_ballast", Severity::Info)]),
            0
        );
    }

    #[test]
    fn exit_code_is_one_with_a_warning() {
        assert_eq!(
            exit_code_for(&[finding("mutagen_active", Severity::Warn)]),
            1
        );
    }

    #[test]
    fn exit_code_is_two_with_a_critical_finding() {
        assert_eq!(
            exit_code_for(&[
                finding("mutagen_active", Severity::Warn),
                finding("container_load", Severity::Critical),
            ]),
            2
        );
    }

    #[test]
    fn tty_report_starts_with_verdict() {
        let text = format_tty(&sample_report(Vec::new()), false);
        assert_eq!(
            text.lines().next(),
            Some("All calm  Nothing is slowing your Mac down.")
        );
    }

    #[test]
    fn formats_tty_report_with_vitals() {
        let text = format_tty(&sample_report(Vec::new()), false);
        assert!(text.contains("3.27"));
        assert!(text.contains("10P"));
        assert!(text.contains("4E"));
        assert!(text.contains("1204140"));
        assert!(text.contains("36"));
        assert!(text.to_lowercase().contains("no findings"));
    }

    #[test]
    fn formats_tty_report_with_docker_containers() {
        let mut report = sample_report(Vec::new());
        report.docker.containers = vec![
            vitals_core::types::DockerContainer {
                id: "abc".to_string(),
                name: "ddev-witte-web".to_string(),
                image: "ddev/ddev-webserver".to_string(),
                cpu_percent: 0.1,
                mem_bytes: 0,
                ddev_managed: true,
                ddev_project: Some("witte".to_string()),
                compose_project: Some("ddev-witte".to_string()),
            },
            vitals_core::types::DockerContainer {
                id: "def".to_string(),
                name: "verdi-middleware-postgres-1".to_string(),
                image: "postgres:17".to_string(),
                cpu_percent: 0.0,
                mem_bytes: 0,
                ddev_managed: false,
                ddev_project: None,
                compose_project: Some("verdi-middleware".to_string()),
            },
        ];
        let text = format_tty(&report, false);
        assert!(text.contains("2 container(s)"));
        assert!(text.contains("1 unmanaged"));
    }

    #[test]
    fn formats_tty_report_with_findings() {
        let text = format_tty(
            &sample_report(vec![finding("container_load", Severity::Critical)]),
            false,
        );
        assert!(text.contains("container_load"));
        assert!(text.contains("critical"));
        assert!(text.contains("some_action"));
    }

    #[test]
    fn build_action_poweroff_needs_no_target_or_report() {
        let config = Config::default();
        assert_eq!(
            build_action("poweroff", None, None, None, &config, 0).unwrap(),
            Action::Poweroff
        );
    }

    #[test]
    fn build_action_stop_backup_needs_no_target_or_report() {
        let config = Config::default();
        assert_eq!(
            build_action("stop_backup", None, None, None, &config, 0).unwrap(),
            Action::StopBackup
        );
    }

    #[test]
    fn build_action_add_exclusions_uses_config_paths_without_a_report() {
        let mut config = Config::default();
        config.watch.timemachine_exclusions = vec!["~/.orbstack".to_string()];
        assert_eq!(
            build_action("add_exclusions", None, None, None, &config, 0).unwrap(),
            Action::AddExclusions(vec!["~/.orbstack".to_string()])
        );
    }

    #[test]
    fn build_action_add_exclusions_errors_when_none_configured() {
        let config = Config::default();
        assert!(build_action("add_exclusions", None, None, None, &config, 0).is_err());
    }

    #[test]
    fn build_action_kill_orphaned_agents_collects_orphaned_pids() {
        let mut report = sample_report(Vec::new());
        report.processes.acp_agents = vec![
            AcpAgent {
                pid: 1,
                etime_seconds: 0,
                ide_version: "PhpStorm2025.3".to_string(),
                orphaned: true,
            },
            AcpAgent {
                pid: 2,
                etime_seconds: 0,
                ide_version: "PhpStorm2026.2".to_string(),
                orphaned: false,
            },
        ];
        let config = Config::default();
        assert_eq!(
            build_action(
                "kill_orphaned_agents",
                None,
                Some(&report),
                None,
                &config,
                0
            )
            .unwrap(),
            Action::KillOrphanedAgents(vec![1])
        );
    }

    #[test]
    fn build_action_kill_orphaned_agents_errors_when_none_found() {
        let report = sample_report(Vec::new());
        let config = Config::default();
        assert!(build_action(
            "kill_orphaned_agents",
            None,
            Some(&report),
            None,
            &config,
            0
        )
        .is_err());
    }

    #[test]
    fn build_action_kill_orphaned_agents_errors_without_a_report() {
        let config = Config::default();
        assert!(build_action("kill_orphaned_agents", None, None, None, &config, 0).is_err());
    }

    fn sample_process(pid: u32, cpu_percent: f64, etime_seconds: u64) -> ProcessEntry {
        ProcessEntry {
            pid,
            ppid: 0,
            etime_seconds,
            cpu_percent,
            rss_bytes: 0,
            comm: "/usr/bin/stuck".to_string(),
            command: "/usr/bin/stuck".to_string(),
        }
    }

    #[test]
    fn build_action_kill_runaway_processes_collects_runaway_pids() {
        let processes = vec![
            sample_process(4242, 750.0, 21 * 60),
            sample_process(4243, 5.0, 21 * 60),
        ];
        let config = Config::default();
        assert_eq!(
            build_action(
                "kill_runaway_processes",
                None,
                None,
                Some(&processes),
                &config,
                0
            )
            .unwrap(),
            Action::KillRunawayProcesses(vec![4242])
        );
    }

    #[test]
    fn build_action_kill_runaway_processes_errors_when_none_found() {
        let processes = vec![sample_process(1, 5.0, 20 * 60)];
        let config = Config::default();
        assert!(build_action(
            "kill_runaway_processes",
            None,
            None,
            Some(&processes),
            &config,
            0
        )
        .is_err());
    }

    #[test]
    fn build_action_kill_runaway_processes_errors_without_a_process_list() {
        let config = Config::default();
        assert!(build_action("kill_runaway_processes", None, None, None, &config, 0).is_err());
    }

    #[test]
    fn build_action_stop_project_requires_target() {
        let config = Config::default();
        assert!(build_action("stop_project", None, None, None, &config, 0).is_err());
        assert_eq!(
            build_action("stop_project", Some("witte"), None, None, &config, 0).unwrap(),
            Action::StopProject("witte".to_string())
        );
    }

    #[test]
    fn build_action_start_project_requires_target() {
        let config = Config::default();
        assert!(build_action("start_project", None, None, None, &config, 0).is_err());
        assert_eq!(
            build_action("start_project", Some("witte"), None, None, &config, 0).unwrap(),
            Action::StartProject("witte".to_string())
        );
    }

    #[test]
    fn build_action_project_names_cannot_look_like_flags() {
        let config = Config::default();
        for action in ["start_project", "stop_project"] {
            assert!(build_action(action, Some("--all"), None, None, &config, 0).is_err());
            assert!(build_action(action, Some("-x"), None, None, &config, 0).is_err());
            assert!(build_action(action, Some(""), None, None, &config, 0).is_err());
        }
    }

    #[test]
    fn build_action_kill_process_requires_target() {
        let config = Config::default();
        assert!(build_action("kill_process", None, None, Some(&[]), &config, 0).is_err());
        assert!(build_action("kill_process", Some("90548"), None, Some(&[]), &config, 0).is_err());
    }

    #[test]
    fn build_action_kill_process_verifies_identity() {
        let config = Config::default();
        let processes = [ProcessEntry {
            pid: 90548,
            ppid: 1,
            etime_seconds: 600,
            cpu_percent: 0.0,
            rss_bytes: 0,
            comm: "node".to_string(),
            command: "node".to_string(),
        }];
        assert_eq!(
            build_action(
                "kill_process",
                Some("90548@999400"),
                None,
                Some(&processes),
                &config,
                1_000_000
            )
            .unwrap(),
            Action::KillProcess {
                pid: 90548,
                started_at: 999_400
            }
        );
        assert!(build_action(
            "kill_process",
            Some("90548@999000"),
            None,
            Some(&processes),
            &config,
            1_000_000
        )
        .is_err());
    }

    #[test]
    fn build_action_kill_session_is_unknown() {
        let config = Config::default();
        let err = build_action("kill_session", Some("90548"), None, None, &config, 0).unwrap_err();
        assert!(err.contains("unknown action"));
    }

    #[test]
    fn build_action_rejects_unknown_action() {
        let config = Config::default();
        assert!(build_action("launch_the_missiles", None, None, None, &config, 0).is_err());
    }

    #[test]
    fn build_action_prune_docker_images_needs_no_target_or_report() {
        let config = Config::default();
        assert_eq!(
            build_action("prune_docker_images", None, None, None, &config, 0).unwrap(),
            Action::PruneDockerImages
        );
    }
}
