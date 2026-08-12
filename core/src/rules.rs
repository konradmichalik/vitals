//! The 8 rules from concept doc §5, plus `unmanaged_docker_containers`
//! (containers running outside DDEV's management, e.g. a plain `docker
//! compose up` project) added after live testing showed such containers
//! were completely invisible: condition over probe data → named diagnosis
//! → suggested action. Every finding names the specific offender (which
//! project, which PID, how many) — never just a category.

use crate::config::Config;
use crate::probes::processes::ProcessEntry;
use crate::types::{DockerContainer, Finding, Severity, VitalsReport};

pub fn evaluate(
    report: &VitalsReport,
    processes: &[ProcessEntry],
    config: &Config,
) -> Vec<Finding> {
    [
        backup_scanning_container_data(report, config),
        backup_paths_not_excluded(report),
        container_load(report, config),
        mutagen_active(processes),
        uptime_ballast(report, config),
        orphaned_acp_agents(report),
        stale_claude_sessions(report, config),
        ddev_project_problems(report),
        unmanaged_docker_containers(report),
    ]
    .into_iter()
    .flatten()
    .collect()
}

fn unmanaged_docker_containers(report: &VitalsReport) -> Option<Finding> {
    let unmanaged: Vec<&DockerContainer> = report
        .docker
        .containers
        .iter()
        .filter(|c| !c.ddev_managed)
        .collect();

    if unmanaged.is_empty() {
        return None;
    }

    let mut projects: Vec<&str> = unmanaged
        .iter()
        .map(|c| c.compose_project.as_deref().unwrap_or(c.name.as_str()))
        .collect();
    projects.sort_unstable();
    projects.dedup();

    Some(Finding {
        rule: "unmanaged_docker_containers".to_string(),
        severity: Severity::Info,
        message: format!(
            "{} container(s) across {} project(s) running outside DDEV: {}",
            unmanaged.len(),
            projects.len(),
            projects.join(", ")
        ),
        actions: Vec::new(),
    })
}

fn load_exceeds_critical(report: &VitalsReport, config: &Config) -> bool {
    let p_cores = f64::from(report.system.cores.performance);
    report.system.load.m1 > p_cores * config.thresholds.load_critical_factor
}

fn backup_scanning_container_data(report: &VitalsReport, config: &Config) -> Option<Finding> {
    let changed_items = report.time_machine.changed_item_count.unwrap_or(0);
    let scanning = load_exceeds_critical(report, config)
        && report.time_machine.running
        && changed_items > config.thresholds.changed_items_warn;
    scanning.then(|| Finding {
        rule: "backup_scanning_container_data".to_string(),
        severity: Severity::Critical,
        message: format!("Time Machine is scanning container data ({changed_items} changed items)"),
        actions: vec!["stop_backup".to_string(), "add_exclusions".to_string()],
    })
}

fn backup_paths_not_excluded(report: &VitalsReport) -> Option<Finding> {
    let included: Vec<&str> = report
        .time_machine
        .exclusions
        .iter()
        .filter(|exclusion| !exclusion.excluded)
        .map(|exclusion| exclusion.path.as_str())
        .collect();

    (!included.is_empty()).then(|| Finding {
        rule: "backup_paths_not_excluded".to_string(),
        severity: Severity::Warn,
        message: format!(
            "Container paths are included in Time Machine backups: {}",
            included.join(", ")
        ),
        actions: vec!["add_exclusions".to_string()],
    })
}

fn container_load(report: &VitalsReport, config: &Config) -> Option<Finding> {
    let orbstack_cpu = report
        .processes
        .orbstack
        .as_ref()
        .map(|o| o.cpu_percent)
        .unwrap_or(0.0);
    let busy = load_exceeds_critical(report, config)
        && !report.time_machine.running
        && orbstack_cpu > 200.0;

    busy.then(|| Finding {
        rule: "container_load".to_string(),
        severity: Severity::Critical,
        message: format!(
            "Container load — {} project(s) running",
            report.ddev.running.len()
        ),
        actions: vec!["list_running_projects".to_string(), "poweroff".to_string()],
    })
}

fn mutagen_active(processes: &[ProcessEntry]) -> Option<Finding> {
    let active = processes
        .iter()
        .any(|process| process.comm.contains("mutagen") && process.cpu_percent > 20.0);

    active.then(|| Finding {
        rule: "mutagen_active".to_string(),
        severity: Severity::Warn,
        message: "Mutagen filesystem sync is active — consider DDEV's performance_mode: none"
            .to_string(),
        actions: Vec::new(),
    })
}

fn uptime_ballast(report: &VitalsReport, config: &Config) -> Option<Finding> {
    let thresholds = &config.thresholds;
    let compressor_warn_bytes = (thresholds.compressor_warn_gb * 1024.0 * 1024.0 * 1024.0) as u64;
    let uptime_warn_seconds = (thresholds.uptime_warn_days * 86400.0) as u64;
    let ballast = report.system.memory.compressor_bytes > compressor_warn_bytes
        && report.system.uptime_seconds > uptime_warn_seconds;

    ballast.then(|| Finding {
        rule: "uptime_ballast".to_string(),
        severity: Severity::Info,
        message: format!(
            "Accumulated memory ballast — restart recommended ({:.1} GB compressed, {} days uptime)",
            report.system.memory.compressor_bytes as f64 / 1024.0 / 1024.0 / 1024.0,
            report.system.uptime_seconds / 86400,
        ),
        actions: Vec::new(),
    })
}

fn orphaned_acp_agents(report: &VitalsReport) -> Option<Finding> {
    let orphaned: Vec<&str> = report
        .processes
        .acp_agents
        .iter()
        .filter(|agent| agent.orphaned)
        .map(|agent| agent.ide_version.as_str())
        .collect();

    if !orphaned.is_empty() {
        return Some(Finding {
            rule: "orphaned_acp_agents".to_string(),
            severity: Severity::Warn,
            message: format!(
                "{} orphaned PhpStorm ACP agent(s) ({})",
                orphaned.len(),
                orphaned.join(", ")
            ),
            actions: vec!["kill_orphaned_agents".to_string()],
        });
    }

    (report.processes.acp_agents.len() > 3).then(|| Finding {
        rule: "orphaned_acp_agents".to_string(),
        severity: Severity::Warn,
        message: format!(
            "{} PhpStorm ACP agents running — possible leak",
            report.processes.acp_agents.len()
        ),
        actions: vec!["kill_orphaned_agents".to_string()],
    })
}

fn stale_claude_sessions(report: &VitalsReport, config: &Config) -> Option<Finding> {
    let stale_seconds = (config.thresholds.stale_session_days * 86400.0) as u64;
    let stale_count = report
        .processes
        .claude_sessions
        .iter()
        .filter(|session| session.etime_seconds > stale_seconds)
        .count();

    (stale_count > 0).then(|| Finding {
        rule: "stale_claude_sessions".to_string(),
        severity: Severity::Info,
        message: format!(
            "{stale_count} Claude Code session(s) older than {} days",
            config.thresholds.stale_session_days
        ),
        actions: vec!["list_with_age".to_string()],
    })
}

fn ddev_project_problems(report: &VitalsReport) -> Option<Finding> {
    (!report.ddev.problems.is_empty()).then(|| Finding {
        rule: "ddev_project_problems".to_string(),
        severity: Severity::Warn,
        message: format!(
            "Project(s) in problem state — possible restart loop: {}",
            report.ddev.problems.join(", ")
        ),
        actions: vec!["stop_project".to_string()],
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{
        AcpAgent, ClaudeSession, CoreCount, DdevInfo, DockerContainer, DockerInfo, LoadAverage,
        MemoryInfo, OrbstackProcess, PressureLevel, ProcessesInfo, SystemInfo, TimeMachineInfo,
        TmExclusion,
    };

    fn base_report() -> VitalsReport {
        VitalsReport {
            schema_version: 1,
            timestamp: "2026-08-12T09:52:00Z".to_string(),
            system: SystemInfo {
                uptime_seconds: 3600,
                load: LoadAverage {
                    m1: 1.0,
                    m5: 1.0,
                    m15: 1.0,
                },
                cores: CoreCount {
                    performance: 10,
                    efficiency: 4,
                    total: 14,
                },
                memory: MemoryInfo {
                    pressure_level: PressureLevel::Normal,
                    free_percent: 50,
                    page_size_bytes: 16384,
                    compressor_bytes: 0,
                    swap_used_bytes: 0,
                    pageouts: 0,
                },
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
            findings: Vec::new(),
        }
    }

    fn process(comm: &str, cpu_percent: f64) -> ProcessEntry {
        ProcessEntry {
            pid: 1,
            ppid: 0,
            etime_seconds: 30,
            cpu_percent,
            rss_bytes: 0,
            comm: comm.to_string(),
            command: comm.to_string(),
        }
    }

    fn finds(
        report: &VitalsReport,
        processes: &[ProcessEntry],
        config: &Config,
        rule: &str,
    ) -> bool {
        evaluate(report, processes, config)
            .iter()
            .any(|finding| finding.rule == rule)
    }

    #[test]
    fn backup_scanning_container_data_fires_when_load_high_and_tm_scanning_many_items() {
        let mut report = base_report();
        report.system.load.m1 = 20.0;
        report.time_machine.running = true;
        report.time_machine.changed_item_count = Some(57_818);
        let config = Config::default();

        assert!(finds(
            &report,
            &[],
            &config,
            "backup_scanning_container_data"
        ));
        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "backup_scanning_container_data")
            .unwrap();
        assert_eq!(finding.severity, Severity::Critical);
        assert!(finding.message.contains("57818") || finding.message.contains("57,818"));
        assert!(finding.actions.contains(&"stop_backup".to_string()));
    }

    #[test]
    fn backup_scanning_container_data_does_not_fire_when_load_normal() {
        let mut report = base_report();
        report.time_machine.running = true;
        report.time_machine.changed_item_count = Some(57_818);
        let config = Config::default();

        assert!(!finds(
            &report,
            &[],
            &config,
            "backup_scanning_container_data"
        ));
    }

    #[test]
    fn backup_paths_not_excluded_fires_when_a_configured_path_is_included() {
        let mut report = base_report();
        report.time_machine.exclusions = vec![
            TmExclusion {
                path: "~/.orbstack".to_string(),
                excluded: false,
            },
            TmExclusion {
                path: "~/.ddev".to_string(),
                excluded: true,
            },
        ];
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "backup_paths_not_excluded")
            .unwrap();
        assert_eq!(finding.severity, Severity::Warn);
        assert!(finding.message.contains("~/.orbstack"));
        assert!(!finding.message.contains("~/.ddev"));
    }

    #[test]
    fn backup_paths_not_excluded_is_silent_when_all_excluded() {
        let mut report = base_report();
        report.time_machine.exclusions = vec![TmExclusion {
            path: "~/.orbstack".to_string(),
            excluded: true,
        }];
        let config = Config::default();

        assert!(!finds(&report, &[], &config, "backup_paths_not_excluded"));
    }

    #[test]
    fn container_load_fires_when_load_high_tm_idle_and_orbstack_busy() {
        let mut report = base_report();
        report.system.load.m1 = 20.0;
        report.time_machine.running = false;
        report.ddev.running = vec!["witte".to_string(), "vhw".to_string()];
        report.processes.orbstack = Some(OrbstackProcess {
            pid: 1,
            cpu_percent: 437.7,
            rss_bytes: 0,
        });
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "container_load")
            .unwrap();
        assert_eq!(finding.severity, Severity::Critical);
        assert!(finding.message.contains('2'));
        assert!(finding.actions.contains(&"poweroff".to_string()));
    }

    #[test]
    fn container_load_does_not_fire_when_backup_is_running() {
        let mut report = base_report();
        report.system.load.m1 = 20.0;
        report.time_machine.running = true;
        report.processes.orbstack = Some(OrbstackProcess {
            pid: 1,
            cpu_percent: 437.7,
            rss_bytes: 0,
        });
        let config = Config::default();

        assert!(!finds(&report, &[], &config, "container_load"));
    }

    #[test]
    fn mutagen_active_fires_on_busy_mutagen_process() {
        let report = base_report();
        let processes = vec![process("/opt/homebrew/bin/mutagen", 25.0)];
        let config = Config::default();

        let finding = evaluate(&report, &processes, &config)
            .into_iter()
            .find(|f| f.rule == "mutagen_active")
            .unwrap();
        assert_eq!(finding.severity, Severity::Warn);
    }

    #[test]
    fn mutagen_active_does_not_fire_when_idle() {
        let report = base_report();
        let processes = vec![process("/opt/homebrew/bin/mutagen", 1.0)];
        let config = Config::default();

        assert!(!finds(&report, &processes, &config, "mutagen_active"));
    }

    #[test]
    fn uptime_ballast_fires_on_old_uptime_and_large_compressor() {
        let mut report = base_report();
        report.system.uptime_seconds = 10 * 86400;
        report.system.memory.compressor_bytes = 10 * 1024 * 1024 * 1024;
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "uptime_ballast")
            .unwrap();
        assert_eq!(finding.severity, Severity::Info);
        assert!(finding.actions.is_empty());
    }

    #[test]
    fn orphaned_acp_agents_fires_for_retired_ide_version() {
        let mut report = base_report();
        report.processes.acp_agents = vec![AcpAgent {
            pid: 1,
            etime_seconds: 100,
            ide_version: "PhpStorm2026.1".to_string(),
            orphaned: true,
        }];
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "orphaned_acp_agents")
            .unwrap();
        assert_eq!(finding.severity, Severity::Warn);
        assert!(finding.message.contains("PhpStorm2026.1"));
        assert!(finding
            .actions
            .contains(&"kill_orphaned_agents".to_string()));
    }

    #[test]
    fn orphaned_acp_agents_fires_when_more_than_three_running() {
        let mut report = base_report();
        report.processes.acp_agents = (0..4)
            .map(|pid| AcpAgent {
                pid,
                etime_seconds: 100,
                ide_version: "PhpStorm2026.2".to_string(),
                orphaned: false,
            })
            .collect();
        let config = Config::default();

        assert!(finds(&report, &[], &config, "orphaned_acp_agents"));
    }

    #[test]
    fn stale_claude_sessions_fires_past_threshold() {
        let mut report = base_report();
        report.processes.claude_sessions = vec![ClaudeSession {
            pid: 1,
            etime_seconds: 4 * 86400,
            cpu_percent: 1.0,
            rss_bytes: 0,
            kind: "cli".to_string(),
            version: "2.1.228".to_string(),
        }];
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "stale_claude_sessions")
            .unwrap();
        assert_eq!(finding.severity, Severity::Info);
    }

    #[test]
    fn ddev_project_problems_fires_and_names_the_project() {
        let mut report = base_report();
        report.ddev.problems = vec!["pagetree-facets".to_string()];
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "ddev_project_problems")
            .unwrap();
        assert_eq!(finding.severity, Severity::Warn);
        assert!(finding.message.contains("pagetree-facets"));
        assert!(finding.actions.contains(&"stop_project".to_string()));
    }

    #[test]
    fn no_rules_fire_on_a_healthy_report() {
        let report = base_report();
        let config = Config::default();

        assert!(evaluate(&report, &[], &config).is_empty());
    }

    fn docker_container(
        name: &str,
        ddev_managed: bool,
        ddev_project: Option<&str>,
        compose_project: Option<&str>,
    ) -> DockerContainer {
        DockerContainer {
            id: "abc123".to_string(),
            name: name.to_string(),
            image: "postgres:17".to_string(),
            cpu_percent: 0.0,
            mem_bytes: 0,
            ddev_managed,
            ddev_project: ddev_project.map(str::to_string),
            compose_project: compose_project.map(str::to_string),
        }
    }

    #[test]
    fn unmanaged_docker_containers_fires_and_names_the_compose_project() {
        let mut report = base_report();
        report.docker.containers = vec![
            docker_container("ddev-witte-web", true, Some("witte"), Some("ddev-witte")),
            docker_container(
                "verdi-middleware-postgres-1",
                false,
                None,
                Some("verdi-middleware"),
            ),
        ];
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "unmanaged_docker_containers")
            .unwrap();
        assert_eq!(finding.severity, Severity::Info);
        assert!(finding.message.contains("verdi-middleware"));
        assert!(!finding.message.contains("witte"));
    }

    #[test]
    fn unmanaged_docker_containers_dedupes_by_compose_project() {
        let mut report = base_report();
        report.docker.containers = vec![
            docker_container(
                "verdi-middleware-postgres-1",
                false,
                None,
                Some("verdi-middleware"),
            ),
            docker_container(
                "verdi-middleware-mariadb-1",
                false,
                None,
                Some("verdi-middleware"),
            ),
        ];
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "unmanaged_docker_containers")
            .unwrap();
        assert!(finding.message.contains('2'));
        assert_eq!(finding.message.matches("verdi-middleware").count(), 1);
    }

    #[test]
    fn unmanaged_docker_containers_falls_back_to_container_name_without_compose_project() {
        let mut report = base_report();
        report.docker.containers = vec![docker_container("standalone-redis", false, None, None)];
        let config = Config::default();

        let finding = evaluate(&report, &[], &config)
            .into_iter()
            .find(|f| f.rule == "unmanaged_docker_containers")
            .unwrap();
        assert!(finding.message.contains("standalone-redis"));
    }

    #[test]
    fn unmanaged_docker_containers_is_silent_when_everything_is_ddev_managed() {
        let mut report = base_report();
        report.docker.containers = vec![docker_container(
            "ddev-witte-web",
            true,
            Some("witte"),
            Some("ddev-witte"),
        )];
        let config = Config::default();

        assert!(!finds(&report, &[], &config, "unmanaged_docker_containers"));
    }

    /// Real live bug: DDEV's own shared router/ssh-agent containers have
    /// no project-specific `ddev_project` (empty `com.ddev.site-name`),
    /// but they ARE DDEV-managed (`com.ddev.platform=ddev`) — they must
    /// not be reported as "running outside DDEV".
    #[test]
    fn unmanaged_docker_containers_ignores_ddev_shared_infra_with_no_project() {
        let mut report = base_report();
        report.docker.containers = vec![docker_container(
            "ddev-router",
            true,
            None,
            Some("ddev-router"),
        )];
        let config = Config::default();

        assert!(!finds(&report, &[], &config, "unmanaged_docker_containers"));
    }
}
