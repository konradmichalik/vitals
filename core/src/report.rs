//! Assembles the §6 JSON contract by running every probe and classifying
//! the raw process table. `findings` is left empty here — `rules::evaluate`
//! fills it in as a separate pass, so this stays pure data collection.

use crate::config::Config;
use crate::error::VitalsError;
use crate::probes::processes::ProcessEntry;
use crate::{classify, probes, types};

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
        free_percent: free_percent(free_bytes, total_bytes),
        page_size_bytes: vm_stat.page_size_bytes,
        compressor_bytes: vm_stat.compressor_bytes(),
        swap_used_bytes: swap.used_bytes,
        pageouts: vm_stat.pageouts,
    };

    let system = types::SystemInfo {
        uptime_seconds,
        load,
        cores,
        memory,
    };

    let tm_status = probes::time_machine::status()?;
    let time_machine = types::TimeMachineInfo {
        running: tm_status.running,
        phase: tm_status.phase,
        changed_item_count: tm_status.changed_item_count,
        exclusions: probes::time_machine::check_exclusions(&config.watch.timemachine_exclusions)?,
    };

    let ddev_projects = probes::ddev::list()?;
    let ddev = probes::ddev::summarize(&ddev_projects);

    let dangling_images = probes::docker::dangling_images()?;
    let docker = types::DockerInfo {
        containers: probes::docker::list()?,
        dangling_image_count: dangling_images.count,
        reclaimable_bytes: dangling_images.reclaimable_bytes,
    };

    let process_entries = probes::processes::list()?;
    let processes = types::ProcessesInfo {
        claude_sessions: classify::claude_sessions(&process_entries),
        acp_agents: classify::acp_agents(&process_entries, &config.ide.retired_versions),
        orbstack: probes::orbstack::find()?,
    };

    let report = types::VitalsReport {
        schema_version: types::SCHEMA_VERSION,
        timestamp: timestamp_now()?,
        system,
        time_machine,
        ddev,
        docker,
        processes,
        findings: Vec::new(),
    };

    Ok((report, process_entries))
}

fn free_percent(free_bytes: u64, total_bytes: u64) -> u8 {
    if total_bytes == 0 {
        return 0;
    }
    ((free_bytes as f64 / total_bytes as f64) * 100.0)
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
    fn computes_free_percent() {
        assert_eq!(free_percent(6_442_450_944, 25_769_803_776), 25);
    }

    #[test]
    fn free_percent_of_zero_total_is_zero() {
        assert_eq!(free_percent(1024, 0), 0);
    }

    #[test]
    fn free_percent_rounds_to_nearest() {
        assert_eq!(free_percent(1, 3), 33);
    }
}
