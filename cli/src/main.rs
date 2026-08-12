use std::io::{IsTerminal, Write};
use std::process::ExitCode;

use clap::Parser;
use vitals_core::actions::Action;
use vitals_core::config::Config;
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

    /// Apply a remediation action: poweroff, stop_project, stop_backup,
    /// add_exclusions, kill_orphaned_agents, kill_session
    #[arg(long, value_name = "ACTION")]
    fix: Option<String>,

    /// Target for actions that need one (a DDEV project name or a PID)
    #[arg(long, value_name = "VALUE")]
    target: Option<String>,

    /// Show what an action would do without executing it
    #[arg(long)]
    dry_run: bool,
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

fn run_fix(
    action_name: &str,
    target: Option<&str>,
    dry_run: bool,
    config: &Config,
    json: bool,
    use_color: bool,
) -> ExitCode {
    let report = if action_name == "kill_orphaned_agents" {
        match vitals_core::report::collect(config) {
            Ok((report, _processes)) => Some(report),
            Err(err) => {
                report_error(&err, json, use_color);
                return ExitCode::FAILURE;
            }
        }
    } else {
        None
    };

    let action = match build_action(action_name, target, report.as_ref(), config) {
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

    if config.actions.require_confirmation && !confirm(&action) {
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

fn confirm(action: &Action) -> bool {
    print!("Run `{}`? [y/N] ", action.describe());
    let _ = std::io::stdout().flush();
    let mut input = String::new();
    if std::io::stdin().read_line(&mut input).is_err() {
        return false;
    }
    matches!(input.trim().to_lowercase().as_str(), "y" | "yes")
}

/// `report` is only needed by `kill_orphaned_agents` — callers should skip
/// the (expensive, DDEV-touching) `collect()` call entirely for every other
/// action rather than fetch a report that will go unused.
fn build_action(
    name: &str,
    target: Option<&str>,
    report: Option<&VitalsReport>,
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
        "stop_project" => {
            let name = target.ok_or("`stop_project` requires --target <project-name>")?;
            Ok(Action::StopProject(name.to_string()))
        }
        "kill_session" => {
            let pid = target.ok_or("`kill_session` requires --target <pid>")?;
            let pid: u32 = pid
                .parse()
                .map_err(|_| format!("`{pid}` is not a valid PID"))?;
            Ok(Action::KillSession(pid))
        }
        other => Err(format!(
            "unknown action `{other}` (expected one of: poweroff, stop_project, stop_backup, \
             add_exclusions, kill_orphaned_agents, kill_session)"
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
        AcpAgent, CoreCount, DdevInfo, LoadAverage, MemoryInfo, PressureLevel, ProcessesInfo,
        SystemInfo, TimeMachineInfo,
    };

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
                    page_size_bytes: 16384,
                    compressor_bytes: 10_905_550_848,
                    swap_used_bytes: 21_690_548_224,
                    pageouts: 7_301_205,
                },
            },
            time_machine: TimeMachineInfo {
                running: false,
                phase: None,
                changed_item_count: None,
                exclusions: Vec::new(),
            },
            ddev: DdevInfo::default(),
            processes: ProcessesInfo::default(),
            findings,
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
            build_action("poweroff", None, None, &config).unwrap(),
            Action::Poweroff
        );
    }

    #[test]
    fn build_action_stop_backup_needs_no_target_or_report() {
        let config = Config::default();
        assert_eq!(
            build_action("stop_backup", None, None, &config).unwrap(),
            Action::StopBackup
        );
    }

    #[test]
    fn build_action_add_exclusions_uses_config_paths_without_a_report() {
        let mut config = Config::default();
        config.watch.timemachine_exclusions = vec!["~/.orbstack".to_string()];
        assert_eq!(
            build_action("add_exclusions", None, None, &config).unwrap(),
            Action::AddExclusions(vec!["~/.orbstack".to_string()])
        );
    }

    #[test]
    fn build_action_add_exclusions_errors_when_none_configured() {
        let config = Config::default();
        assert!(build_action("add_exclusions", None, None, &config).is_err());
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
            build_action("kill_orphaned_agents", None, Some(&report), &config).unwrap(),
            Action::KillOrphanedAgents(vec![1])
        );
    }

    #[test]
    fn build_action_kill_orphaned_agents_errors_when_none_found() {
        let report = sample_report(Vec::new());
        let config = Config::default();
        assert!(build_action("kill_orphaned_agents", None, Some(&report), &config).is_err());
    }

    #[test]
    fn build_action_kill_orphaned_agents_errors_without_a_report() {
        let config = Config::default();
        assert!(build_action("kill_orphaned_agents", None, None, &config).is_err());
    }

    #[test]
    fn build_action_stop_project_requires_target() {
        let config = Config::default();
        assert!(build_action("stop_project", None, None, &config).is_err());
        assert_eq!(
            build_action("stop_project", Some("witte"), None, &config).unwrap(),
            Action::StopProject("witte".to_string())
        );
    }

    #[test]
    fn build_action_kill_session_parses_pid() {
        let config = Config::default();
        assert!(build_action("kill_session", Some("not-a-pid"), None, &config).is_err());
        assert_eq!(
            build_action("kill_session", Some("90548"), None, &config).unwrap(),
            Action::KillSession(90548)
        );
    }

    #[test]
    fn build_action_rejects_unknown_action() {
        let config = Config::default();
        assert!(build_action("launch_the_missiles", None, None, &config).is_err());
    }
}
