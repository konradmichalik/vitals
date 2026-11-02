//! Groups containers, sessions and processes into the "Top consumers" list.
//! Each process or container is counted in exactly one group.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::classify;
use crate::config::Config;
use crate::probes::processes::ProcessEntry;
use crate::types::{SuggestedAction, VitalsReport};

const MIN_MEM_BYTES: u64 = 100 * 1024 * 1024;
const MIN_CPU_PERCENT: f64 = 1.0;
const MAX_GROUPS: usize = 12;
const GIB: f64 = 1024.0 * 1024.0 * 1024.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ConsumerKind {
    DdevProject,
    ClaudeCli,
    App,
    Process,
    OrbstackOverhead,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Consumer {
    pub id: String,
    pub kind: ConsumerKind,
    pub label: String,
    pub detail: Option<String>,
    pub cpu_percent: f64,
    pub mem_bytes: u64,
    pub children: Vec<ConsumerChild>,
    pub action: Option<SuggestedAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConsumerChild {
    pub label: String,
    pub detail: Option<String>,
    pub cpu_percent: f64,
    pub mem_bytes: u64,
    pub action: Option<SuggestedAction>,
}

pub fn build(
    report: &VitalsReport,
    processes: &[ProcessEntry],
    config: &Config,
    now: u64,
) -> Vec<Consumer> {
    let home = std::env::var("HOME").ok();
    build_with_home(report, processes, config, now, home.as_deref())
}

fn build_with_home(
    report: &VitalsReport,
    processes: &[ProcessEntry],
    config: &Config,
    now: u64,
    home: Option<&str>,
) -> Vec<Consumer> {
    let mut groups = ddev_groups(report);
    groups.extend(claude_group(report, config, now, home));
    groups.extend(process_groups(report, processes, now));
    groups.extend(orbstack_group(report));

    groups.retain(|g| g.cpu_percent >= MIN_CPU_PERCENT || g.mem_bytes >= MIN_MEM_BYTES);
    groups.sort_by(|a, b| b.mem_bytes.cmp(&a.mem_bytes));
    groups.truncate(MAX_GROUPS);
    groups
}

fn ddev_groups(report: &VitalsReport) -> Vec<Consumer> {
    let mut by_project: BTreeMap<&str, Vec<&crate::types::DockerContainer>> = BTreeMap::new();
    for container in &report.docker.containers {
        if let Some(project) = container.ddev_project.as_deref() {
            by_project.entry(project).or_default().push(container);
        }
    }
    by_project
        .into_iter()
        .map(|(project, containers)| {
            let mem_bytes: u64 = containers.iter().map(|c| c.mem_bytes).sum();
            Consumer {
                id: format!("ddev:{project}"),
                kind: ConsumerKind::DdevProject,
                label: format!("ddev · {project}"),
                detail: Some(format!("{} containers", containers.len())),
                cpu_percent: containers.iter().map(|c| c.cpu_percent).sum(),
                mem_bytes,
                children: containers
                    .iter()
                    .map(|c| ConsumerChild {
                        label: c.name.clone(),
                        detail: None,
                        cpu_percent: c.cpu_percent,
                        mem_bytes: c.mem_bytes,
                        action: None,
                    })
                    .collect(),
                action: Some(SuggestedAction {
                    action: "stop_project".to_string(),
                    target: Some(project.to_string()),
                    label: "Stop".to_string(),
                    estimate: Some(format!("about {:.1} GB", mem_bytes as f64 / GIB)),
                }),
            }
        })
        .collect()
}

fn claude_group(
    report: &VitalsReport,
    config: &Config,
    now: u64,
    home: Option<&str>,
) -> Option<Consumer> {
    let sessions = &report.processes.claude_sessions;
    if sessions.is_empty() {
        return None;
    }
    let stale_seconds = config.thresholds.stale_session_days * 86_400.0;
    let children = sessions
        .iter()
        .map(|s| ConsumerChild {
            label: s
                .working_directory
                .as_deref()
                .map(|dir| tilde(dir, home))
                .unwrap_or_else(|| format!("pid {}", s.pid)),
            detail: None,
            cpu_percent: s.cpu_percent,
            mem_bytes: s.rss_bytes,
            action: (s.etime_seconds as f64 > stale_seconds).then(|| SuggestedAction {
                action: "kill_process".to_string(),
                target: Some(kill_target(s.pid, now.saturating_sub(s.etime_seconds))),
                label: "End".to_string(),
                estimate: None,
            }),
        })
        .collect();
    Some(Consumer {
        id: "claude".to_string(),
        kind: ConsumerKind::ClaudeCli,
        label: "Claude CLI".to_string(),
        detail: Some(format!("{} sessions", sessions.len())),
        cpu_percent: sessions.iter().map(|s| s.cpu_percent).sum(),
        mem_bytes: sessions.iter().map(|s| s.rss_bytes).sum(),
        children,
        action: None,
    })
}

fn process_groups(report: &VitalsReport, processes: &[ProcessEntry], now: u64) -> Vec<Consumer> {
    let mut apps: BTreeMap<String, (Consumer, usize)> = BTreeMap::new();
    let mut plain = Vec::new();
    for p in processes {
        if p.comm.contains("OrbStack.app/")
            || report
                .processes
                .claude_sessions
                .iter()
                .any(|s| s.pid == p.pid)
        {
            continue;
        }
        match bundle_name(&p.comm) {
            Some(name) => {
                let (group, count) = apps
                    .entry(name.to_string())
                    .or_insert_with(|| (app_group(name), 0));
                group.cpu_percent += p.cpu_percent;
                group.mem_bytes += p.rss_bytes;
                *count += 1;
            }
            None => plain.push(plain_group(p, now)),
        }
    }
    let mut groups: Vec<Consumer> = apps
        .into_values()
        .map(|(mut group, count)| {
            group.detail = Some(format!("{count} processes"));
            group
        })
        .collect();
    groups.extend(plain);
    groups
}

fn app_group(name: &str) -> Consumer {
    Consumer {
        id: format!("app:{name}"),
        kind: ConsumerKind::App,
        label: name.to_string(),
        detail: None,
        cpu_percent: 0.0,
        mem_bytes: 0,
        children: Vec::new(),
        action: None,
    }
}

fn plain_group(p: &ProcessEntry, now: u64) -> Consumer {
    Consumer {
        id: format!("proc:{}", p.pid),
        kind: ConsumerKind::Process,
        label: classify::command_label(&p.command),
        detail: None,
        cpu_percent: p.cpu_percent,
        mem_bytes: p.rss_bytes,
        children: Vec::new(),
        action: is_killable(p).then(|| SuggestedAction {
            action: "kill_process".to_string(),
            target: Some(kill_target(p.pid, now.saturating_sub(p.etime_seconds))),
            label: "Quit".to_string(),
            estimate: None,
        }),
    }
}

/// Never offer to kill launchd, system daemons or vitals itself.
fn is_killable(p: &ProcessEntry) -> bool {
    const SYSTEM_PREFIXES: [&str; 4] = ["/System/", "/usr/sbin/", "/usr/libexec/", "/sbin/"];
    p.pid > 1
        && p.pid != std::process::id()
        && !SYSTEM_PREFIXES
            .iter()
            .any(|prefix| p.comm.starts_with(prefix))
}

fn orbstack_group(report: &VitalsReport) -> Option<Consumer> {
    let orbstack = report.processes.orbstack.as_ref()?;
    let container_mem: u64 = report.docker.containers.iter().map(|c| c.mem_bytes).sum();
    Some(Consumer {
        id: "orbstack".to_string(),
        kind: ConsumerKind::OrbstackOverhead,
        label: "OrbStack VM".to_string(),
        detail: Some("Container runtime".to_string()),
        cpu_percent: orbstack.cpu_percent,
        mem_bytes: orbstack.rss_bytes.saturating_sub(container_mem),
        children: Vec::new(),
        action: None,
    })
}

fn kill_target(pid: u32, started_at: u64) -> String {
    format!("{pid}@{started_at}")
}

/// `/Applications/PhpStorm.app/Contents/MacOS/phpstorm` gives `PhpStorm`.
fn bundle_name(comm: &str) -> Option<&str> {
    let end = comm.find(".app/")?;
    let start = comm[..end].rfind('/').map_or(0, |i| i + 1);
    Some(&comm[start..end])
}

fn tilde(path: &str, home: Option<&str>) -> String {
    match home {
        Some(home) if !home.is_empty() => match path.strip_prefix(home) {
            Some("") => "~".to_string(),
            Some(rest) if rest.starts_with('/') => format!("~{rest}"),
            _ => path.to_string(),
        },
        _ => path.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::*;

    const GB: u64 = 1_000_000_000;
    const NOW: u64 = 1_000_000;

    fn report() -> VitalsReport {
        VitalsReport {
            schema_version: SCHEMA_VERSION,
            timestamp: "2026-11-02T09:00:00Z".to_string(),
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
                    used_percent: 50,
                    page_size_bytes: 16384,
                    compressor_bytes: 0,
                    swap_used_bytes: 0,
                    pageouts: 0,
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
            findings: Vec::new(),
            consumers: Vec::new(),
        }
    }

    fn container(name: &str, project: Option<&str>, mem_bytes: u64) -> DockerContainer {
        DockerContainer {
            id: name.to_string(),
            name: name.to_string(),
            image: "img".to_string(),
            cpu_percent: 0.5,
            mem_bytes,
            ddev_managed: project.is_some(),
            ddev_project: project.map(str::to_string),
            compose_project: None,
        }
    }

    fn process(pid: u32, comm: &str, command: &str, rss_bytes: u64) -> ProcessEntry {
        ProcessEntry {
            pid,
            ppid: 1,
            etime_seconds: 600,
            cpu_percent: 0.0,
            rss_bytes,
            comm: comm.to_string(),
            command: command.to_string(),
        }
    }

    fn session(pid: u32, etime_seconds: u64) -> ClaudeSession {
        ClaudeSession {
            pid,
            etime_seconds,
            cpu_percent: 0.0,
            rss_bytes: 300 * 1024 * 1024,
            kind: "cli".to_string(),
            version: "2.1.0".to_string(),
            working_directory: Some("/Users/me/Sites/vitals".to_string()),
        }
    }

    fn run(report: &VitalsReport, processes: &[ProcessEntry]) -> Vec<Consumer> {
        build_with_home(
            report,
            processes,
            &Config::default(),
            NOW,
            Some("/Users/me"),
        )
    }

    #[test]
    fn ddev_containers_group_by_project() {
        let mut r = report();
        r.docker.containers = vec![
            container("witte-db", Some("witte"), 1_600_000_000),
            container("witte-web", Some("witte"), 900_000_000),
            container("other", None, 5 * GB),
        ];
        let groups = run(&r, &[]);
        assert_eq!(groups.len(), 1);
        let group = &groups[0];
        assert_eq!(group.id, "ddev:witte");
        assert_eq!(group.label, "ddev · witte");
        assert_eq!(group.mem_bytes, 2_500_000_000);
        assert_eq!(group.children.len(), 2);
        let action = group.action.as_ref().unwrap();
        assert_eq!(action.action, "stop_project");
        assert_eq!(action.target.as_deref(), Some("witte"));
        assert_eq!(action.label, "Stop");
        assert_eq!(action.estimate.as_deref(), Some("about 2.3 GB"));
    }

    #[test]
    fn app_bundle_processes_group_by_bundle() {
        let processes = vec![
            process(
                10,
                "/Applications/PhpStorm.app/Contents/MacOS/phpstorm",
                "phpstorm",
                2 * GB,
            ),
            process(
                11,
                "/Applications/PhpStorm.app/Contents/Helpers/jbr",
                "jbr",
                GB,
            ),
        ];
        let groups = run(&report(), &processes);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].kind, ConsumerKind::App);
        assert_eq!(groups[0].label, "PhpStorm");
        assert_eq!(groups[0].mem_bytes, 3 * GB);
        assert_eq!(groups[0].detail.as_deref(), Some("2 processes"));
        assert!(groups[0].action.is_none());
    }

    #[test]
    fn plain_process_gets_kill_target_with_start_time() {
        let mut p = process(48213, "/usr/local/bin/node", "node server.js", GB);
        p.etime_seconds = 600;
        let groups = run(&report(), &[p]);
        let action = groups[0].action.as_ref().unwrap();
        assert_eq!(groups[0].kind, ConsumerKind::Process);
        assert_eq!(action.action, "kill_process");
        assert_eq!(action.target.as_deref(), Some("48213@999400"));
        assert_eq!(action.label, "Quit");
    }

    #[test]
    fn orbstack_overhead_never_negative() {
        let mut r = report();
        r.processes.orbstack = Some(OrbstackProcess {
            pid: 5,
            cpu_percent: 3.0,
            rss_bytes: GB,
        });
        r.docker.containers = vec![container("a", None, 2 * GB)];
        let groups = run(&r, &[]);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].kind, ConsumerKind::OrbstackOverhead);
        assert_eq!(groups[0].mem_bytes, 0);
    }

    #[test]
    fn small_groups_are_dropped() {
        let mut quiet = process(1, "/bin/a", "a", 99 * 1024 * 1024);
        quiet.cpu_percent = 0.9;
        let mut busy = process(2, "/bin/b", "b", 1024);
        busy.cpu_percent = 1.0;
        let heavy = process(3, "/bin/c", "c", 100 * 1024 * 1024);
        let groups = run(&report(), &[quiet, busy, heavy]);
        let ids: Vec<&str> = groups.iter().map(|g| g.id.as_str()).collect();
        assert_eq!(ids, vec!["proc:3", "proc:2"]);
    }

    #[test]
    fn stale_claude_session_child_gets_end_action() {
        let mut r = report();
        r.processes.claude_sessions = vec![session(70, 4 * 86_400), session(71, 7_200)];
        let mut config = Config::default();
        config.thresholds.stale_session_days = 3.0;
        let groups = build_with_home(&r, &[], &config, NOW, Some("/Users/me"));
        let group = &groups[0];
        assert_eq!(group.kind, ConsumerKind::ClaudeCli);
        assert_eq!(group.label, "Claude CLI");
        assert_eq!(group.children[0].label, "~/Sites/vitals");
        let end = group.children[0].action.as_ref().unwrap();
        assert_eq!(end.action, "kill_process");
        assert_eq!(end.target.as_deref(), Some("70@654400"));
        assert_eq!(end.label, "End");
        assert!(group.children[1].action.is_none());
    }

    #[test]
    fn claude_pids_and_orbstack_app_are_not_regrouped() {
        let mut r = report();
        r.processes.claude_sessions = vec![session(70, 60)];
        let processes = vec![
            process(70, "claude", "claude", GB),
            process(
                80,
                "/Applications/OrbStack.app/Contents/MacOS/OrbStack",
                "OrbStack",
                GB,
            ),
        ];
        let groups = run(&r, &processes);
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].id, "claude");
    }

    #[test]
    fn groups_are_sorted_by_memory_and_capped() {
        let processes: Vec<ProcessEntry> = (0..15)
            .map(|i| process(100 + i, "/bin/x", "x", (i as u64 + 1) * GB))
            .collect();
        let groups = run(&report(), &processes);
        assert_eq!(groups.len(), 12);
        assert_eq!(groups[0].id, "proc:114");
    }

    #[test]
    fn system_process_gets_no_kill_action() {
        let p = process(500, "/usr/libexec/foo", "foo", GB);
        let groups = run(&report(), &[p]);
        assert_eq!(groups[0].kind, ConsumerKind::Process);
        assert!(groups[0].action.is_none());
    }

    #[test]
    fn own_process_gets_no_kill_action() {
        let p = process(std::process::id(), "/bin/vitals", "vitals", GB);
        let groups = run(&report(), &[p]);
        assert_eq!(groups.len(), 1);
        assert!(groups[0].action.is_none());
    }
}
