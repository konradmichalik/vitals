//! Assembles the §6 JSON contract by running every probe and classifying
//! the raw process table. `findings` is left empty here — `rules::evaluate`
//! fills it in as a separate pass, so this stays pure data collection.

use crate::config::Config;
use crate::error::VitalsError;
use crate::probes::processes::ProcessEntry;
use crate::{activity, classify, consumers, probes, types};

/// Returns the report alongside the raw process table, since `rules`
/// needs entries (e.g. a `mutagen` process) that never make it into the
/// curated §6 JSON contract.
pub fn collect(config: &Config) -> Result<(types::VitalsReport, Vec<ProcessEntry>), VitalsError> {
    let uptime_seconds = probes::uptime::seconds()?;
    let load = probes::load::read()?;
    let cores = probes::cores::read()?;

    let vm_stat = probes::vm_stat::read()?;
    let swap = probes::swap::read()?;
    let total_bytes = probes::memory::total_bytes()?;
    let free_bytes = vm_stat.free_pages * vm_stat.page_size_bytes;

    let memory = types::MemoryInfo {
        pressure_level: probes::memory::pressure_level()?,
        free_percent: percent_of(free_bytes, total_bytes),
        used_percent: percent_of(vm_stat.used_bytes(), total_bytes),
        page_size_bytes: vm_stat.page_size_bytes,
        compressor_bytes: vm_stat.compressor_bytes(),
        swap_used_bytes: swap.used_bytes,
        pageouts: vm_stat.pageouts,
        total_bytes,
        available_bytes: total_bytes.saturating_sub(vm_stat.used_bytes()),
    };

    let cpu = probes::cpu::read()?;

    let system = types::SystemInfo {
        uptime_seconds,
        load,
        cores,
        memory,
        cpu,
    };

    let tm_status = probes::time_machine::status()?;
    let time_machine = types::TimeMachineInfo {
        running: tm_status.running,
        phase: tm_status.phase,
        changed_item_count: tm_status.changed_item_count,
        exclusions: probes::time_machine::check_exclusions(&config.watch.timemachine_exclusions)?,
    };

    let ddev_projects = probes::ddev::list()?;
    let mut ddev = probes::ddev::summarize(&ddev_projects);

    let dangling_images = probes::docker::dangling_images()?;
    let docker = types::DockerInfo {
        containers: probes::docker::list()?,
        dangling_image_count: dangling_images.count,
        reclaimable_bytes: dangling_images.reclaimable_bytes,
    };

    let now = activity::now_unix();
    ddev.projects = ddev_project_infos(&ddev_projects, &docker.containers, config, now);

    let process_entries = probes::processes::list()?;
    let processes = types::ProcessesInfo {
        claude_sessions: claude_sessions(&process_entries),
        acp_agents: classify::acp_agents(&process_entries, &config.ide.retired_versions),
        orbstack: probes::orbstack::find()?,
        top_by_cpu: top_processes(&process_entries, 5),
    };

    let home = std::env::var("HOME").ok();
    let groups = consumers::groups(&consumers::Inputs {
        processes: &process_entries,
        sessions: &processes.claude_sessions,
        acp_agents: &processes.acp_agents,
        containers: &docker.containers,
        ddev_projects: &ddev.projects,
        config,
        home: home.as_deref(),
    });

    let mut report = types::VitalsReport {
        schema_version: types::SCHEMA_VERSION,
        timestamp: timestamp_now()?,
        system,
        time_machine,
        ddev,
        docker,
        processes,
        findings: Vec::new(),
        disk: types::DiskInfo {
            total_bytes: probes::disk::total_bytes().ok(),
        },
        consumers: Vec::new(),
        quick_wins: Vec::new(),
        incidents: probes::incidents::recent(14, 10, std::time::SystemTime::now()),
    };
    report.quick_wins = consumers::quick_wins(&groups, &report, &process_entries, config);
    report.consumers = groups;

    Ok((report, process_entries))
}

/// Joins `ddev list` with the containers' live usage, and records which
/// projects were busy in this sample so idle time can be measured across
/// runs (`activity`). A project counts as busy when its containers
/// together use at least `idle.ddev_cpu_percent`.
fn ddev_project_infos(
    projects: &[probes::ddev::DdevProject],
    containers: &[types::DockerContainer],
    config: &Config,
    now: u64,
) -> Vec<types::DdevProjectInfo> {
    let mut infos: Vec<types::DdevProjectInfo> = projects
        .iter()
        .map(|project| {
            let mine = containers
                .iter()
                .filter(|c| c.ddev_project.as_deref() == Some(project.name.as_str()));
            let (mem_bytes, cpu_percent) =
                mine.fold((0, 0.0), |(m, c), x| (m + x.mem_bytes, c + x.cpu_percent));
            types::DdevProjectInfo {
                name: project.name.clone(),
                status: project.status.clone(),
                approot: project.location.clone(),
                mem_bytes,
                cpu_percent,
                idle_seconds: None,
            }
        })
        .collect();

    let observations: Vec<activity::Observation> = infos
        .iter()
        .filter(|info| info.status == "running")
        .map(|info| activity::Observation {
            key: format!("ddev:{}", info.name),
            active: info.cpu_percent >= config.idle.ddev_cpu_percent,
        })
        .collect();

    if let Some(path) = activity::default_path() {
        let state = activity::update(&activity::load(&path), &observations, now);
        activity::save(&path, &state);
        for info in infos.iter_mut().filter(|info| info.status == "running") {
            info.idle_seconds = activity::idle_seconds(&state, &format!("ddev:{}", info.name), now);
        }
    }
    infos
}

/// `classify::claude_session_candidates` can only narrow by display name
/// (real CLI sessions and PhpStorm ACP agents both show `comm ==
/// "claude"`) — confirming each candidate and getting its version needs
/// an actual process lookup, which belongs here alongside the other
/// I/O-performing probe calls, not in the pure `classify` module.
fn claude_sessions(processes: &[ProcessEntry]) -> Vec<types::ClaudeSession> {
    classify::claude_session_candidates(processes)
        .into_iter()
        .filter_map(|process| {
            let info = probes::claude_cli::resolve(process.pid)?;
            let idle_seconds = info.working_directory.as_deref().and_then(|dir| {
                probes::transcripts::seconds_since_last_write(dir, std::time::SystemTime::now())
            });
            Some(types::ClaudeSession {
                tree_rss_bytes: consumers::tree_rss(processes, process.pid),
                idle_seconds,
                pid: process.pid,
                etime_seconds: process.etime_seconds,
                cpu_percent: process.cpu_percent,
                rss_bytes: process.rss_bytes,
                kind: "cli".to_string(),
                version: info.version,
                working_directory: info.working_directory,
            })
        })
        .collect()
}

/// Sorted highest-CPU-first; `comm` is stripped to its bare name to match
/// how `rules::runaway_processes` already names offenders.
fn top_processes(processes: &[ProcessEntry], limit: usize) -> Vec<types::TopProcess> {
    let mut sorted: Vec<&ProcessEntry> = processes.iter().collect();
    sorted.sort_by(|a, b| b.cpu_percent.total_cmp(&a.cpu_percent));
    sorted
        .into_iter()
        .take(limit)
        .map(|p| types::TopProcess {
            pid: p.pid,
            name: p.comm.rsplit('/').next().unwrap_or(&p.comm).to_string(),
            cpu_percent: p.cpu_percent,
        })
        .collect()
}

fn percent_of(part_bytes: u64, total_bytes: u64) -> u8 {
    if total_bytes == 0 {
        return 0;
    }
    ((part_bytes as f64 / total_bytes as f64) * 100.0)
        .round()
        .clamp(0.0, 100.0) as u8
}

fn timestamp_now() -> Result<String, VitalsError> {
    time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .map_err(|err| VitalsError::ParseError {
            command: "timestamp".to_string(),
            reason: err.to_string(),
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn computes_percent_of() {
        assert_eq!(percent_of(6_442_450_944, 25_769_803_776), 25);
    }

    #[test]
    fn percent_of_zero_total_is_zero() {
        assert_eq!(percent_of(1024, 0), 0);
    }

    #[test]
    fn percent_of_rounds_to_nearest() {
        assert_eq!(percent_of(1, 3), 33);
    }

    fn process(pid: u32, comm: &str, cpu_percent: f64) -> ProcessEntry {
        ProcessEntry {
            pid,
            ppid: 0,
            etime_seconds: 30,
            cpu_percent,
            rss_bytes: 0,
            comm: comm.to_string(),
            command: comm.to_string(),
        }
    }

    #[test]
    fn top_processes_orders_by_cpu_percent_descending() {
        let processes = vec![
            process(1, "a", 10.0),
            process(2, "b", 90.0),
            process(3, "c", 50.0),
        ];
        let top = top_processes(&processes, 5);
        assert_eq!(top.iter().map(|p| p.pid).collect::<Vec<_>>(), vec![2, 3, 1]);
    }

    #[test]
    fn top_processes_respects_limit() {
        let processes = vec![
            process(1, "a", 10.0),
            process(2, "b", 90.0),
            process(3, "c", 50.0),
        ];
        let top = top_processes(&processes, 2);
        assert_eq!(top.len(), 2);
    }

    #[test]
    fn top_processes_strips_full_path_to_bare_name() {
        let processes = vec![process(1, "/usr/local/bin/node", 10.0)];
        let top = top_processes(&processes, 5);
        assert_eq!(top[0].name, "node");
    }
}
