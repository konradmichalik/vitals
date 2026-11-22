use std::io::{IsTerminal, Write};
use std::process::ExitCode;

use clap::Parser;
use vitals_core::actions::Action;
use vitals_core::config::{Config, Overrides};
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
    /// stop_backup, add_exclusions, kill_orphaned_agents,
    /// kill_runaway_processes, kill_session, prune_docker_images, quit_app,
    /// restart_app, free_idle
    #[arg(long, value_name = "ACTION")]
    fix: Option<String>,

    /// Target for actions that need one (a DDEV project name, a PID or an
    /// app name). stop_project, start_project and kill_session accept
    /// several, separated by commas.
    #[arg(long, value_name = "VALUE")]
    target: Option<String>,

    /// What `--fix free_idle` may free: any of ddev, agents, orphans,
    /// separated by commas. Defaults to all three.
    #[arg(long, value_name = "LIST")]
    scope: Option<String>,

    /// Minutes without activity before a project or session counts as
    /// idle. Overrides `idle.after_minutes` from ~/.vitals.toml.
    #[arg(long, value_name = "MINUTES")]
    idle_minutes: Option<f64>,

    /// Project names or session directories that are never freed,
    /// separated by commas. Replaces `idle.protected` from ~/.vitals.toml.
    #[arg(long, value_name = "LIST")]
    protect: Option<String>,

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

    let overrides = Overrides {
        idle_after_minutes: cli.idle_minutes,
        protected: cli.protect.as_deref().map(split_list),
        fresh: None,
    };
    let config = match vitals_core::config::load() {
        Ok(config) => config.with_overrides(&overrides),
        Err(err) => {
            report_error(&err, cli.json, use_color);
            return ExitCode::FAILURE;
        }
    };

    if let Some(action_name) = &cli.fix {
        return run_fix(
            action_name,
            cli.target.as_deref(),
            cli.scope.as_deref(),
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

fn split_list(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn run_fix(
    action_name: &str,
    target: Option<&str>,
    scope: Option<&str>,
    dry_run: bool,
    yes: bool,
    config: &Config,
    json: bool,
    use_color: bool,
) -> ExitCode {
    let needs_process_snapshot = matches!(
        action_name,
        "kill_orphaned_agents" | "kill_runaway_processes" | "free_idle"
    );
    let (report, processes) = if needs_process_snapshot {
        match vitals_core::report::collect(config) {
            Ok((report, processes)) => (Some(report), Some(processes)),
            Err(err) => {
                report_error(&err, json, use_color);
                return ExitCode::FAILURE;
            }
        }
    } else {
        (None, None)
    };

    let action = match build_action(
        action_name,
        target,
        scope,
        report.as_ref(),
        processes.as_deref(),
        config,
    ) {
        Ok(action) => action,
        Err(message) => {
            eprintln!("vitals: {message}");
            return ExitCode::FAILURE;
        }
    };

    // Checked before the dry run as well, so a preview never shows a
    // command that the real run would refuse.
    if let Err(message) = action.validate() {
        eprintln!("vitals: {message}");
        return ExitCode::FAILURE;
    }

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

/// `report`/`processes` are only needed by `kill_orphaned_agents`/
/// `kill_runaway_processes` — callers should skip the (expensive,
/// DDEV-touching) `collect()` call entirely for every other action rather
/// than fetch a report that will go unused.
fn build_action(
    name: &str,
    target: Option<&str>,
    scope: Option<&str>,
    report: Option<&VitalsReport>,
    processes: Option<&[ProcessEntry]>,
    config: &Config,
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
            let names = targets(target, "`stop_project` requires --target <project-name>")?;
            Ok(batch(names.into_iter().map(Action::StopProject).collect()))
        }
        "start_project" => {
            let names = targets(target, "`start_project` requires --target <project-name>")?;
            Ok(batch(names.into_iter().map(Action::StartProject).collect()))
        }
        "kill_session" => {
            let raw = targets(target, "`kill_session` requires --target <pid>")?;
            let pids = raw
                .iter()
                .map(|pid| {
                    pid.parse::<u32>()
                        .map_err(|_| format!("`{pid}` is not a valid PID"))
                })
                .collect::<Result<Vec<u32>, String>>()?;
            Ok(batch(pids.into_iter().map(Action::KillSession).collect()))
        }
        "quit_app" | "restart_app" => {
            let app = target.ok_or(format!("`{name}` requires --target <app-name>"))?;
            Action::validate_app_name(app)?;
            Ok(if name == "quit_app" {
                Action::QuitApp(app.to_string())
            } else {
                Action::RestartApp(app.to_string())
            })
        }
        "free_idle" => {
            let report = report.ok_or("internal error: no report collected for free_idle")?;
            free_idle(report, scope)
        }
        "prune_docker_images" => Ok(Action::PruneDockerImages),
        other => Err(format!(
            "unknown action `{other}` (expected one of: {})",
            vitals_core::actions::ACTION_NAMES.join(", ")
        )),
    }
}

fn targets(target: Option<&str>, missing: &str) -> Result<Vec<String>, String> {
    let list = target.map(split_list).unwrap_or_default();
    if list.is_empty() {
        return Err(missing.to_string());
    }
    Ok(list)
}

fn batch(mut actions: Vec<Action>) -> Action {
    if actions.len() == 1 {
        actions.remove(0)
    } else {
        Action::Batch(actions)
    }
}

const FREE_IDLE_SCOPES: &[&str] = &["ddev", "agents", "orphans"];

/// Re-derives the idle set from a fresh report, exactly as the quick wins
/// were derived, so a stale list from an earlier poll can never decide
/// what gets stopped.
fn free_idle(report: &VitalsReport, scope: Option<&str>) -> Result<Action, String> {
    let scopes = scope
        .map(split_list)
        .unwrap_or_else(|| FREE_IDLE_SCOPES.iter().map(|s| s.to_string()).collect());
    if let Some(unknown) = scopes
        .iter()
        .find(|s| !FREE_IDLE_SCOPES.contains(&s.as_str()))
    {
        return Err(format!(
            "unknown scope `{unknown}` (expected any of: {})",
            FREE_IDLE_SCOPES.join(", ")
        ));
    }
    let idle = vitals_core::consumers::idle_targets(&report.consumers);
    let mut actions = Vec::new();
    if scopes.iter().any(|s| s == "ddev") {
        actions.extend(idle.ddev_projects.into_iter().map(Action::StopProject));
    }
    if scopes.iter().any(|s| s == "agents") {
        actions.extend(idle.session_pids.into_iter().map(Action::KillSession));
    }
    if scopes.iter().any(|s| s == "orphans") && !idle.orphaned_agent_pids.is_empty() {
        actions.push(Action::KillOrphanedAgents(idle.orphaned_agent_pids));
    }
    if actions.is_empty() {
        return Err("nothing idle to free".to_string());
    }
    Ok(batch(actions))
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

    let gb = |bytes: u64| bytes as f64 / 1024.0 / 1024.0 / 1024.0;
    out.push_str(&format!(
        "\nmemory left    {:.1} GB of {:.0} GB\n",
        gb(system.memory.available_bytes),
        gb(system.memory.total_bytes),
    ));
    if !report.quick_wins.is_empty() {
        out.push_str("\nQuick wins:\n");
        for win in &report.quick_wins {
            let gain = if win.reclaimable_bytes > 0 {
                format!("{:>5.1} GB  ", gb(win.reclaimable_bytes))
            } else {
                " ".repeat(10)
            };
            let command = if win.targets.is_empty() {
                format!("vitals --fix {}", win.action)
            } else {
                format!(
                    "vitals --fix {} --target {}",
                    win.action,
                    win.targets.join(",")
                )
            };
            out.push_str(&format!(
                "  {gain}{} ({})\n            {command}\n",
                win.title, win.detail
            ));
        }
    }
    if !report.consumers.is_empty() {
        out.push_str("\nTop consumers:\n");
        for group in report.consumers.iter().take(5) {
            let idle = if group.idle_bytes > 0 {
                format!(", {:.1} GB idle", gb(group.idle_bytes))
            } else {
                String::new()
            };
            out.push_str(&format!(
                "  {:>5.1} GB  {}{idle}\n",
                gb(group.mem_bytes),
                group.name
            ));
        }
    }
    if let Some(incident) = report.incidents.first() {
        out.push_str(&format!(
            "\nLast memory incident: {} (largest process: {})\n",
            incident.date,
            incident.largest_process.as_deref().unwrap_or("unknown")
        ));
    }

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
                    total_bytes: 25_769_803_776,
                    available_bytes: 6_442_450_944,
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
            disk: Default::default(),
            consumers: Vec::new(),
            quick_wins: Vec::new(),
            incidents: Vec::new(),
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
            build_action("poweroff", None, None, None, None, &config).unwrap(),
            Action::Poweroff
        );
    }

    #[test]
    fn build_action_stop_backup_needs_no_target_or_report() {
        let config = Config::default();
        assert_eq!(
            build_action("stop_backup", None, None, None, None, &config).unwrap(),
            Action::StopBackup
        );
    }

    #[test]
    fn build_action_add_exclusions_uses_config_paths_without_a_report() {
        let mut config = Config::default();
        config.watch.timemachine_exclusions = vec!["~/.orbstack".to_string()];
        assert_eq!(
            build_action("add_exclusions", None, None, None, None, &config).unwrap(),
            Action::AddExclusions(vec!["~/.orbstack".to_string()])
        );
    }

    #[test]
    fn build_action_add_exclusions_errors_when_none_configured() {
        let config = Config::default();
        assert!(build_action("add_exclusions", None, None, None, None, &config).is_err());
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
                None,
                Some(&report),
                None,
                &config
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
            None,
            Some(&report),
            None,
            &config
        )
        .is_err());
    }

    #[test]
    fn build_action_kill_orphaned_agents_errors_without_a_report() {
        let config = Config::default();
        assert!(build_action("kill_orphaned_agents", None, None, None, None, &config).is_err());
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
                None,
                Some(&processes),
                &config
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
            None,
            Some(&processes),
            &config
        )
        .is_err());
    }

    #[test]
    fn build_action_kill_runaway_processes_errors_without_a_process_list() {
        let config = Config::default();
        assert!(build_action("kill_runaway_processes", None, None, None, None, &config).is_err());
    }

    #[test]
    fn build_action_stop_project_requires_target() {
        let config = Config::default();
        assert!(build_action("stop_project", None, None, None, None, &config).is_err());
        assert_eq!(
            build_action("stop_project", Some("witte"), None, None, None, &config).unwrap(),
            Action::StopProject("witte".to_string())
        );
    }

    #[test]
    fn build_action_kill_session_parses_pid() {
        let config = Config::default();
        assert!(
            build_action("kill_session", Some("not-a-pid"), None, None, None, &config).is_err()
        );
        assert_eq!(
            build_action("kill_session", Some("90548"), None, None, None, &config).unwrap(),
            Action::KillSession(90548)
        );
    }

    #[test]
    fn build_action_accepts_several_targets_as_a_batch() {
        let config = Config::default();
        assert_eq!(
            build_action(
                "stop_project",
                Some("verdi, pagetree"),
                None,
                None,
                None,
                &config
            )
            .unwrap(),
            Action::Batch(vec![
                Action::StopProject("verdi".to_string()),
                Action::StopProject("pagetree".to_string()),
            ])
        );
        assert_eq!(
            build_action("kill_session", Some("1,2"), None, None, None, &config).unwrap(),
            Action::Batch(vec![Action::KillSession(1), Action::KillSession(2)])
        );
        assert_eq!(
            build_action("start_project", Some("witte"), None, None, None, &config).unwrap(),
            Action::StartProject("witte".to_string())
        );
        assert!(build_action("kill_session", Some(","), None, None, None, &config).is_err());
    }

    #[test]
    fn build_action_quit_app_validates_the_name() {
        let config = Config::default();
        assert_eq!(
            build_action("quit_app", Some("Slack"), None, None, None, &config).unwrap(),
            Action::QuitApp("Slack".to_string())
        );
        assert!(build_action("quit_app", Some("a\"b"), None, None, None, &config).is_err());
        assert!(build_action("restart_app", None, None, None, None, &config).is_err());
    }

    fn idle_item(id: &str, target: &str) -> vitals_core::types::ConsumerItem {
        vitals_core::types::ConsumerItem {
            id: id.to_string(),
            name: target.to_string(),
            detail: String::new(),
            mem_bytes: 1024,
            cpu_percent: 0.0,
            idle: true,
            idle_seconds: Some(9000),
            protected: false,
            action: Some(vitals_core::types::ItemAction {
                action: "x".to_string(),
                target: Some(target.to_string()),
                label: "x".to_string(),
                confirm: false,
            }),
        }
    }

    fn report_with_idle_items() -> VitalsReport {
        let mut report = sample_report(Vec::new());
        report.consumers = vec![vitals_core::types::ConsumerGroup {
            id: "mixed".to_string(),
            name: "mixed".to_string(),
            mem_bytes: 3072,
            cpu_percent: 0.0,
            idle_bytes: 3072,
            items: vec![
                idle_item("ddev:verdi", "verdi"),
                idle_item("session:42", "42"),
                idle_item("acp:7", "7"),
            ],
        }];
        report
    }

    #[test]
    fn free_idle_frees_every_kind_by_default_and_respects_the_scope() {
        let config = Config::default();
        let report = report_with_idle_items();
        assert_eq!(
            build_action("free_idle", None, None, Some(&report), None, &config).unwrap(),
            Action::Batch(vec![
                Action::StopProject("verdi".to_string()),
                Action::KillSession(42),
                Action::KillOrphanedAgents(vec![7]),
            ])
        );
        assert_eq!(
            build_action(
                "free_idle",
                None,
                Some("ddev"),
                Some(&report),
                None,
                &config
            )
            .unwrap(),
            Action::StopProject("verdi".to_string())
        );
        assert!(
            build_action("free_idle", None, Some("ram"), Some(&report), None, &config).is_err()
        );
        let empty = sample_report(Vec::new());
        assert!(build_action("free_idle", None, None, Some(&empty), None, &config).is_err());
    }

    #[test]
    fn tty_report_lists_quick_wins_with_their_command() {
        let mut report = sample_report(Vec::new());
        report.quick_wins = vec![vitals_core::types::QuickWin {
            id: "stop_idle_ddev".to_string(),
            title: "Stop 1 idle DDEV project".to_string(),
            detail: "verdi".to_string(),
            reclaimable_bytes: 1_503_238_553,
            action: "stop_project".to_string(),
            targets: vec!["verdi".to_string()],
            label: "Stop".to_string(),
            confirm: false,
            undo_action: Some("start_project".to_string()),
        }];
        let text = format_tty(&report, false);
        assert!(text.contains("Quick wins"));
        assert!(text.contains("1.4 GB"));
        assert!(text.contains("vitals --fix stop_project --target verdi"));
    }

    #[test]
    fn build_action_rejects_unknown_action() {
        let config = Config::default();
        assert!(build_action("launch_the_missiles", None, None, None, None, &config).is_err());
    }

    #[test]
    fn build_action_prune_docker_images_needs_no_target_or_report() {
        let config = Config::default();
        assert_eq!(
            build_action("prune_docker_images", None, None, None, None, &config).unwrap(),
            Action::PruneDockerImages
        );
    }
}
