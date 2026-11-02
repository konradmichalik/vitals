//! The single verdict the menubar hero shows: headline, detail, culprit
//! and one suggested action, derived from the findings and consumers.

use serde::{Deserialize, Serialize};

use crate::config::Config;
use crate::consumers::{self, Consumer, ConsumerKind};
use crate::probes::processes::ProcessEntry;
use crate::rules;
use crate::types::{Finding, Severity, SuggestedAction, VitalsReport};

const GIB: f64 = 1024.0 * 1024.0 * 1024.0;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Verdict {
    pub severity: Option<Severity>,
    pub headline: String,
    pub detail: String,
    pub culprit: Option<Culprit>,
    pub action: Option<SuggestedAction>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Culprit {
    pub id: String,
    pub label: String,
    pub reason: String,
}

impl Verdict {
    pub fn calm() -> Self {
        Self {
            severity: None,
            headline: "All calm".to_string(),
            detail: "Nothing is slowing your Mac down.".to_string(),
            culprit: None,
            action: None,
        }
    }
}

impl Default for Verdict {
    fn default() -> Self {
        Self::calm()
    }
}

/// `processes` and `config` identify the runaway processes, the only ones
/// the verdict may call "running away".
pub fn derive(report: &VitalsReport, processes: &[ProcessEntry], config: &Config) -> Verdict {
    let Some(finding) = pick_finding(&report.findings) else {
        return Verdict::calm();
    };
    let runaway = runaway_consumer(&report.consumers, processes, config);
    match finding.rule.as_str() {
        "load_status" => load_verdict(report, finding, runaway),
        "runaway_processes" => runaway_verdict(finding, runaway),
        "memory_pressure" => memory_verdict(report, finding),
        _ => Verdict {
            severity: Some(finding.severity),
            headline: finding.message.clone(),
            detail: String::new(),
            culprit: None,
            action: None,
        },
    }
}

/// Highest severity wins. On a tie CPU findings beat memory, memory beats the rest.
fn pick_finding(findings: &[Finding]) -> Option<&Finding> {
    let priority = |rule: &str| match rule {
        "load_status" => 3,
        "runaway_processes" => 2,
        "memory_pressure" => 1,
        _ => 0,
    };
    findings
        .iter()
        .filter(|f| f.severity >= Severity::Warn)
        .max_by_key(|f| (f.severity, priority(&f.rule)))
}

fn load_verdict(report: &VitalsReport, finding: &Finding, runaway: Option<&Consumer>) -> Verdict {
    let cores = report.system.cores.performance;
    let ratio = report.system.load.m1 / f64::from(cores.max(1));
    let headline = if finding.severity == Severity::Critical {
        "CPU is saturated"
    } else {
        "CPU is busy"
    };
    let (consumer, reason) = match runaway {
        Some(c) => (Some(c), "is running away"),
        None => (top_by_cpu(&report.consumers), "uses the most CPU"),
    };
    Verdict {
        severity: Some(finding.severity),
        headline: headline.to_string(),
        detail: format!("Load is {ratio:.1}× your {cores} performance cores."),
        culprit: consumer.map(|c| culprit(c, reason)),
        action: consumer.and_then(cpu_action),
    }
}

fn runaway_verdict(finding: &Finding, consumer: Option<&Consumer>) -> Verdict {
    Verdict {
        severity: Some(finding.severity),
        headline: "A process is running away".to_string(),
        detail: consumer.map_or_else(
            || "A process is using a lot of CPU.".to_string(),
            |c| format!("{} averages {:.0}% CPU.", c.label, c.cpu_percent),
        ),
        culprit: consumer.map(|c| culprit(c, "is running away")),
        action: consumer.and_then(|c| c.action.clone()),
    }
}

fn memory_verdict(report: &VitalsReport, finding: &Finding) -> Verdict {
    let (headline, level) = if finding.severity == Severity::Critical {
        ("Memory is critical", "critical")
    } else {
        ("Memory is tight", "elevated")
    };
    let swap_gb = report.system.memory.swap_used_bytes as f64 / GIB;
    let ddev = largest(&report.consumers, Some(ConsumerKind::DdevProject));
    let consumer = ddev.or_else(|| largest(&report.consumers, None));
    Verdict {
        severity: Some(finding.severity),
        headline: headline.to_string(),
        detail: format!("Pressure {level}, {swap_gb:.1} GB in swap."),
        culprit: consumer.map(|c| culprit(c, "holds the most")),
        action: ddev.and_then(|c| c.action.clone()),
    }
}

fn top_by_cpu(consumers: &[Consumer]) -> Option<&Consumer> {
    consumers
        .iter()
        .max_by(|a, b| a.cpu_percent.total_cmp(&b.cpu_percent))
}

/// The busiest process the runaway rule flags, through its own consumer row.
/// None when that row is missing (a Claude session or OrbStack process).
fn runaway_consumer<'a>(
    consumers: &'a [Consumer],
    processes: &[ProcessEntry],
    config: &Config,
) -> Option<&'a Consumer> {
    processes
        .iter()
        .filter(|p| rules::is_runaway(p, config))
        .max_by(|a, b| a.cpu_percent.total_cmp(&b.cpu_percent))
        .and_then(|p| {
            let id = consumers::process_id(p.pid);
            consumers.iter().find(|c| c.id == id)
        })
}

fn largest(consumers: &[Consumer], kind: Option<ConsumerKind>) -> Option<&Consumer> {
    consumers
        .iter()
        .filter(|c| kind.is_none_or(|k| c.kind == k))
        .max_by_key(|c| c.mem_bytes)
}

fn culprit(consumer: &Consumer, reason: &str) -> Culprit {
    Culprit {
        id: consumer.id.clone(),
        label: consumer.label.clone(),
        reason: reason.to_string(),
    }
}

fn cpu_action(consumer: &Consumer) -> Option<SuggestedAction> {
    let cores = (consumer.cpu_percent / 100.0).round().max(1.0) as u32;
    consumer.action.clone().map(|action| SuggestedAction {
        estimate: Some(if cores == 1 {
            "about 1 core".to_string()
        } else {
            format!("about {cores} cores")
        }),
        ..action
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::*;

    fn report(findings: Vec<Finding>, consumers: Vec<Consumer>) -> VitalsReport {
        VitalsReport {
            schema_version: SCHEMA_VERSION,
            timestamp: "2026-11-02T09:00:00Z".to_string(),
            system: SystemInfo {
                uptime_seconds: 3600,
                load: LoadAverage {
                    m1: 25.0,
                    m5: 20.0,
                    m15: 15.0,
                },
                cores: CoreCount {
                    performance: 10,
                    efficiency: 4,
                    total: 14,
                },
                memory: MemoryInfo {
                    pressure_level: PressureLevel::Normal,
                    free_percent: 20,
                    used_percent: 80,
                    page_size_bytes: 16384,
                    compressor_bytes: 0,
                    swap_used_bytes: 3 * 1024 * 1024 * 1024 + 1024 * 1024 * 1024 / 2,
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
            findings,
            consumers,
            verdict: Verdict::calm(),
        }
    }

    fn run(r: &VitalsReport) -> Verdict {
        derive(r, &[], &Config::default())
    }

    fn run_with(r: &VitalsReport, processes: &[ProcessEntry]) -> Verdict {
        derive(r, processes, &Config::default())
    }

    /// Above the default 700% threshold for longer than 20 minutes.
    fn runaway(pid: u32) -> ProcessEntry {
        ProcessEntry {
            pid,
            ppid: 1,
            etime_seconds: 21 * 60,
            cpu_percent: 750.0,
            rss_bytes: 0,
            comm: "/usr/local/bin/node".to_string(),
            command: "node spin.js".to_string(),
        }
    }

    fn finding(rule: &str, severity: Severity) -> Finding {
        Finding {
            rule: rule.to_string(),
            severity,
            message: format!("{rule} fired"),
            actions: Vec::new(),
        }
    }

    fn action(name: &str, target: &str) -> SuggestedAction {
        SuggestedAction {
            action: name.to_string(),
            target: Some(target.to_string()),
            label: name.to_string(),
            estimate: None,
        }
    }

    fn consumer(id: &str, kind: ConsumerKind, cpu: f64, mem_gb: f64) -> Consumer {
        let act = match kind {
            ConsumerKind::DdevProject => Some(action("stop_project", id)),
            ConsumerKind::Process => Some(action("kill_process", id)),
            _ => None,
        };
        Consumer {
            id: id.to_string(),
            kind,
            label: format!("label {id}"),
            detail: None,
            cpu_percent: cpu,
            mem_bytes: (mem_gb * GIB) as u64,
            children: Vec::new(),
            action: act,
        }
    }

    #[test]
    fn load_critical_names_running_away_process() {
        let r = report(
            vec![finding("load_status", Severity::Critical)],
            vec![
                consumer("proc:1", ConsumerKind::Process, 240.0, 1.0),
                consumer("proc:2", ConsumerKind::Process, 50.0, 1.0),
            ],
        );
        let v = run_with(&r, &[runaway(1)]);
        assert_eq!(v.severity, Some(Severity::Critical));
        assert_eq!(v.headline, "CPU is saturated");
        assert_eq!(v.detail, "Load is 2.5× your 10 performance cores.");
        let culprit = v.culprit.unwrap();
        assert_eq!(culprit.id, "proc:1");
        assert_eq!(culprit.label, "label proc:1");
        assert_eq!(culprit.reason, "is running away");
        let act = v.action.unwrap();
        assert_eq!(act.action, "kill_process");
        assert_eq!(act.estimate.as_deref(), Some("about 2 cores"));
    }

    #[test]
    fn load_warn_without_process_uses_most_cpu() {
        let r = report(
            vec![finding("load_status", Severity::Warn)],
            vec![consumer("ddev:a", ConsumerKind::DdevProject, 30.0, 1.0)],
        );
        let v = run(&r);
        assert_eq!(v.headline, "CPU is busy");
        assert_eq!(v.culprit.unwrap().reason, "uses the most CPU");
        let act = v.action.unwrap();
        assert_eq!(act.action, "stop_project");
        assert_eq!(act.estimate.as_deref(), Some("about 1 core"));
    }

    #[test]
    fn runaway_only_names_top_process() {
        let r = report(
            vec![finding("runaway_processes", Severity::Warn)],
            vec![consumer("proc:9", ConsumerKind::Process, 187.0, 1.0)],
        );
        let v = run_with(&r, &[runaway(9)]);
        assert_eq!(v.headline, "A process is running away");
        assert_eq!(v.detail, "label proc:9 averages 187% CPU.");
        assert_eq!(v.culprit.unwrap().reason, "is running away");
        assert_eq!(v.action.unwrap().action, "kill_process");
    }

    #[test]
    fn load_ignores_a_quiet_process_and_names_the_top_consumer() {
        let r = report(
            vec![finding("load_status", Severity::Critical)],
            vec![
                consumer("app:PhpStorm", ConsumerKind::App, 600.0, 4.0),
                consumer("proc:2", ConsumerKind::Process, 2.0, 0.2),
            ],
        );
        let culprit = run(&r).culprit.unwrap();
        assert_eq!(culprit.id, "app:PhpStorm");
        assert_eq!(culprit.reason, "uses the most CPU");
    }

    #[test]
    fn runaway_only_without_its_consumer_names_no_bystander() {
        let r = report(
            vec![Finding {
                message: "1 process(es) sustaining unusually high CPU: node (pid 7, 750% CPU)"
                    .to_string(),
                ..finding("runaway_processes", Severity::Warn)
            }],
            vec![consumer("proc:3", ConsumerKind::Process, 3.0, 2.0)],
        );
        let v = run_with(&r, &[runaway(7)]);
        assert!(v.culprit.is_none() && v.action.is_none());
        assert_eq!(v.detail, "A process is using a lot of CPU.");
    }

    #[test]
    fn runaway_only_names_the_runaway_over_a_busier_process() {
        let r = report(
            vec![finding("runaway_processes", Severity::Warn)],
            vec![
                consumer("proc:5", ConsumerKind::Process, 750.0, 0.1),
                consumer("proc:6", ConsumerKind::Process, 790.0, 0.1),
            ],
        );
        let v = run_with(&r, &[runaway(5)]);
        assert_eq!(v.culprit.unwrap().id, "proc:5");
    }

    #[test]
    fn load_row_wins_over_runaway() {
        let r = report(
            vec![
                finding("runaway_processes", Severity::Warn),
                finding("load_status", Severity::Warn),
            ],
            vec![consumer("proc:9", ConsumerKind::Process, 187.0, 1.0)],
        );
        assert_eq!(run(&r).headline, "CPU is busy");
    }

    #[test]
    fn memory_warn_row() {
        let r = report(
            vec![finding("memory_pressure", Severity::Warn)],
            vec![consumer("ddev:witte", ConsumerKind::DdevProject, 1.0, 3.0)],
        );
        let v = run(&r);
        assert_eq!(v.headline, "Memory is tight");
        assert_eq!(v.detail, "Pressure elevated, 3.5 GB in swap.");
        assert_eq!(v.culprit.unwrap().reason, "holds the most");
    }

    #[test]
    fn memory_critical_row() {
        let r = report(
            vec![finding("memory_pressure", Severity::Critical)],
            Vec::new(),
        );
        let v = run(&r);
        assert_eq!(v.severity, Some(Severity::Critical));
        assert_eq!(v.headline, "Memory is critical");
        assert_eq!(v.detail, "Pressure critical, 3.5 GB in swap.");
        assert!(v.culprit.is_none() && v.action.is_none());
    }

    #[test]
    fn memory_verdict_prefers_ddev_project() {
        let r = report(
            vec![finding("memory_pressure", Severity::Warn)],
            vec![
                consumer("app:Xcode", ConsumerKind::App, 1.0, 4.0),
                consumer("ddev:witte", ConsumerKind::DdevProject, 1.0, 3.1),
            ],
        );
        let v = run(&r);
        assert_eq!(v.culprit.unwrap().id, "ddev:witte");
        assert_eq!(v.action.unwrap().action, "stop_project");
    }

    #[test]
    fn memory_verdict_without_ddev_has_no_action() {
        let r = report(
            vec![finding("memory_pressure", Severity::Warn)],
            vec![consumer("app:Xcode", ConsumerKind::App, 1.0, 4.0)],
        );
        let v = run(&r);
        assert_eq!(v.culprit.unwrap().id, "app:Xcode");
        assert!(v.action.is_none());
    }

    #[test]
    fn other_alerting_finding_uses_its_message() {
        let r = report(
            vec![finding("time_machine_busy", Severity::Warn)],
            Vec::new(),
        );
        let v = run(&r);
        assert_eq!(v.severity, Some(Severity::Warn));
        assert_eq!(v.headline, "time_machine_busy fired");
        assert_eq!(v.detail, "");
        assert!(v.culprit.is_none() && v.action.is_none());
    }

    #[test]
    fn critical_memory_beats_warn_load() {
        let r = report(
            vec![
                finding("load_status", Severity::Warn),
                finding("memory_pressure", Severity::Critical),
            ],
            Vec::new(),
        );
        assert_eq!(run(&r).headline, "Memory is critical");
    }

    #[test]
    fn cpu_wins_tie_against_memory() {
        let r = report(
            vec![
                finding("memory_pressure", Severity::Warn),
                finding("load_status", Severity::Warn),
            ],
            Vec::new(),
        );
        assert_eq!(run(&r).headline, "CPU is busy");
    }

    #[test]
    fn info_findings_keep_calm() {
        let r = report(vec![finding("uptime_ballast", Severity::Info)], Vec::new());
        let v = run(&r);
        assert_eq!(v.headline, "All calm");
        assert_eq!(v.severity, None);
        assert!(v.culprit.is_none() && v.action.is_none());
    }

    #[test]
    fn nothing_alerting_is_calm() {
        assert_eq!(run(&report(Vec::new(), Vec::new())).headline, "All calm");
    }
}
