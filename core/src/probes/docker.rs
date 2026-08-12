//! `docker ps` + `docker stats --no-stream` → per-container name, image,
//! CPU/mem usage, and DDEV/compose-project attribution via labels.
//!
//! OrbStack ships a Docker-CLI-compatible `docker` binary talking to its
//! own runtime, so this probe works unmodified regardless of backend.
//! DDEV containers carry a `com.ddev.site-name` label (empty for DDEV's
//! own shared router container, which is not project-specific); anything
//! without a non-empty one is not DDEV-managed and would otherwise be
//! completely invisible to `vitals` — e.g. a plain `docker compose up`
//! project running alongside DDEV.

use std::collections::HashMap;
use std::time::Duration;

use crate::error::VitalsError;
use crate::types::DockerContainer;

const PS_TIMEOUT: Duration = Duration::from_secs(15);
const STATS_TIMEOUT: Duration = Duration::from_secs(15);
const IMAGES_TIMEOUT: Duration = Duration::from_secs(15);
const PS_COMMAND: &str = "docker ps --format '{{json .}}'";
const STATS_COMMAND: &str = "docker stats --no-stream --format '{{json .}}'";
const IMAGES_COMMAND: &str = "docker images --filter dangling=true --format '{{json .}}'";

#[derive(Debug)]
struct PsEntry {
    id: String,
    name: String,
    image: String,
    ddev_managed: bool,
    ddev_project: Option<String>,
    compose_project: Option<String>,
}

struct StatsEntry {
    id: String,
    cpu_percent: f64,
    mem_bytes: u64,
}

pub fn list() -> Result<Vec<DockerContainer>, VitalsError> {
    let ps_raw = match super::shell::run_with_timeout(
        "docker",
        &["ps", "--format", "{{json .}}"],
        PS_TIMEOUT,
    ) {
        Ok(raw) => raw,
        Err(VitalsError::CommandFailed { source, .. })
            if source.kind() == std::io::ErrorKind::NotFound =>
        {
            return Ok(Vec::new());
        }
        Err(err) => return Err(err),
    };

    let ps_entries = parse_ps(&ps_raw)?;
    let stats_raw = super::shell::run_with_timeout(
        "docker",
        &["stats", "--no-stream", "--format", "{{json .}}"],
        STATS_TIMEOUT,
    )?;
    let stats_entries = parse_stats(&stats_raw)?;

    Ok(merge(ps_entries, &stats_entries))
}

fn parse_ps(raw: &str) -> Result<Vec<PsEntry>, VitalsError> {
    raw.lines()
        .filter(|line| !line.trim().is_empty())
        .map(parse_ps_line)
        .collect()
}

fn parse_ps_line(line: &str) -> Result<PsEntry, VitalsError> {
    let value: serde_json::Value = serde_json::from_str(line)
        .map_err(|source| VitalsError::parse(PS_COMMAND, source.to_string()))?;

    let id = super::json_field(&value, "ID", PS_COMMAND)?;
    let name = super::json_field(&value, "Names", PS_COMMAND)?;
    let image = super::json_field(&value, "Image", PS_COMMAND)?;
    let labels = super::json_field(&value, "Labels", PS_COMMAND).unwrap_or_default();

    Ok(PsEntry {
        id,
        name,
        image,
        ddev_managed: label_value(&labels, "com.ddev.platform").is_some(),
        ddev_project: label_value(&labels, "com.ddev.site-name"),
        compose_project: label_value(&labels, "com.docker.compose.project"),
    })
}

fn parse_stats(raw: &str) -> Result<Vec<StatsEntry>, VitalsError> {
    raw.lines()
        .filter(|line| !line.trim().is_empty())
        .map(parse_stats_line)
        .collect()
}

fn parse_stats_line(line: &str) -> Result<StatsEntry, VitalsError> {
    let value: serde_json::Value = serde_json::from_str(line)
        .map_err(|source| VitalsError::parse(STATS_COMMAND, source.to_string()))?;

    let id = super::json_field(&value, "ID", STATS_COMMAND)?;

    let cpu_raw = super::json_field(&value, "CPUPerc", STATS_COMMAND)?;
    let cpu_percent = cpu_raw.trim_end_matches('%').parse::<f64>().map_err(|_| {
        VitalsError::parse(STATS_COMMAND, format!("`{cpu_raw}` is not a percentage"))
    })?;

    let mem_raw = super::json_field(&value, "MemUsage", STATS_COMMAND)?;
    let used = mem_raw
        .split_once(" / ")
        .map_or(mem_raw.as_str(), |(used, _)| used);
    let mem_bytes = parse_docker_size(used.trim()).ok_or_else(|| {
        VitalsError::parse(STATS_COMMAND, format!("`{used}` is not a valid size"))
    })?;

    Ok(StatsEntry {
        id,
        cpu_percent,
        mem_bytes,
    })
}

fn label_value(labels: &str, key: &str) -> Option<String> {
    labels
        .split(',')
        .find_map(|pair| {
            pair.split_once('=')
                .filter(|(k, _)| *k == key)
                .map(|(_, v)| v)
        })
        .filter(|v| !v.is_empty())
        .map(str::to_string)
}

fn parse_docker_size(value: &str) -> Option<u64> {
    const UNITS: &[(&str, f64)] = &[
        ("GiB", 1024.0 * 1024.0 * 1024.0),
        ("MiB", 1024.0 * 1024.0),
        ("KiB", 1024.0),
        ("B", 1.0),
    ];

    UNITS.iter().find_map(|(suffix, multiplier)| {
        value
            .strip_suffix(suffix)
            .and_then(|number| number.parse::<f64>().ok())
            .map(|number| (number * multiplier).round() as u64)
    })
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct DanglingImages {
    pub count: u32,
    pub reclaimable_bytes: u64,
}

#[derive(Debug)]
struct DanglingImageEntry {
    /// Kept as the raw string, not parsed to a number — we only ever
    /// compare it to `"0"`.
    containers: String,
    size_bytes: u64,
}

/// `docker image prune` (without `-a`) only removes dangling (untagged)
/// images that no container — running or stopped — still references.
/// Only entries with zero referencing containers are counted here, so
/// the reported reclaimable total actually matches what that specific,
/// conservative command would free — not the larger number `-a` would
/// reclaim by also removing tagged-but-unused images.
pub fn dangling_images() -> Result<DanglingImages, VitalsError> {
    match super::shell::run_with_timeout(
        "docker",
        &[
            "images",
            "--filter",
            "dangling=true",
            "--format",
            "{{json .}}",
        ],
        IMAGES_TIMEOUT,
    ) {
        Ok(raw) => parse_dangling_images(&raw),
        Err(VitalsError::CommandFailed { source, .. })
            if source.kind() == std::io::ErrorKind::NotFound =>
        {
            Ok(DanglingImages::default())
        }
        Err(err) => Err(err),
    }
}

fn parse_dangling_images(raw: &str) -> Result<DanglingImages, VitalsError> {
    let entries: Vec<DanglingImageEntry> = raw
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(parse_dangling_image_line)
        .collect::<Result<_, _>>()?;

    let unreferenced: Vec<&DanglingImageEntry> = entries
        .iter()
        .filter(|entry| entry.containers == "0")
        .collect();
    let count = unreferenced.len() as u32;
    let reclaimable_bytes = unreferenced.iter().map(|entry| entry.size_bytes).sum();

    Ok(DanglingImages {
        count,
        reclaimable_bytes,
    })
}

fn parse_dangling_image_line(line: &str) -> Result<DanglingImageEntry, VitalsError> {
    let value: serde_json::Value = serde_json::from_str(line)
        .map_err(|source| VitalsError::parse(IMAGES_COMMAND, source.to_string()))?;

    let containers = super::json_field(&value, "Containers", IMAGES_COMMAND)?;
    let size_str = super::json_field(&value, "Size", IMAGES_COMMAND)?;
    let size_bytes = parse_image_size(&size_str).ok_or_else(|| {
        VitalsError::parse(IMAGES_COMMAND, format!("`{size_str}` is not a valid size"))
    })?;

    Ok(DanglingImageEntry {
        containers,
        size_bytes,
    })
}

/// `docker images`' `Size` column uses go-units' `HumanSize` labels
/// (`B`/`kB`/`MB`/`GB`) — decimal-looking suffixes but an actual 1024
/// multiplier under the hood, unlike `docker stats`' proper IEC
/// `KiB`/`MiB`/`GiB` labels that `parse_docker_size` above handles. The
/// two commands format sizes differently, so this needs its own table.
fn parse_image_size(value: &str) -> Option<u64> {
    const UNITS: &[(&str, f64)] = &[
        ("GB", 1024.0 * 1024.0 * 1024.0),
        ("MB", 1024.0 * 1024.0),
        ("kB", 1024.0),
        ("B", 1.0),
    ];

    UNITS.iter().find_map(|(suffix, multiplier)| {
        value
            .strip_suffix(suffix)
            .and_then(|number| number.parse::<f64>().ok())
            .map(|number| (number * multiplier).round() as u64)
    })
}

fn merge(ps_entries: Vec<PsEntry>, stats_entries: &[StatsEntry]) -> Vec<DockerContainer> {
    let stats_by_id: HashMap<&str, &StatsEntry> =
        stats_entries.iter().map(|s| (s.id.as_str(), s)).collect();

    ps_entries
        .into_iter()
        .filter_map(|entry| {
            let stats = stats_by_id.get(entry.id.as_str())?;
            Some(DockerContainer {
                id: entry.id,
                name: entry.name,
                image: entry.image,
                cpu_percent: stats.cpu_percent,
                mem_bytes: stats.mem_bytes,
                ddev_managed: entry.ddev_managed,
                ddev_project: entry.ddev_project,
                compose_project: entry.compose_project,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Real `docker ps --format '{{json .}}'` lines captured on a live
    // machine, from OrbStack's docker-compatible CLI.
    const DDEV_WEB_PS_LINE: &str = r#"{"Command":"\"/pre-start.sh\"","CreatedAt":"2026-08-12 10:52:20 +0200 CEST","ID":"95b1ce6cdd20","Image":"ddev/ddev-webserver:v1.25.3-pagetree-facets-built","Labels":"build-info=ddev/ddev-webserver:20260703_rfay_traefik_port-arm64 commit=b1ccb25 built Sat Jul  4 02:29:16 UTC 2026 by runner on runnervmqymkm,com.ddev.app-type=php,com.ddev.approot=/Users/k.michalik/Sites/Packages/typo3-pagetree-facets,com.ddev.platform=ddev,com.ddev.site-name=pagetree-facets,com.ddev.webtag=v1.25.3,com.docker.compose.project=ddev-pagetree-facets,com.docker.compose.service=web,maintainer=DDEV <support@ddev.com>","LocalVolumes":"2","Mounts":"...","Names":"ddev-pagetree-facets-web","Networks":"ddev-pagetree-facets_default,ddev_default","Platform":null,"Ports":"127.0.0.1:32838->80/tcp","RunningFor":"About an hour ago","Size":"1.38GB (virtual 3.14GB)","State":"running","Status":"Up About an hour (healthy)"}"#;

    const DDEV_ROUTER_PS_LINE: &str = r#"{"Command":"\"/usr/local/bin/moni…\"","CreatedAt":"2026-08-12 10:28:45 +0200 CEST","ID":"dc734096123b","Image":"ddev/ddev-traefik-router:v1.25.3","Labels":"com.ddev.platform=ddev,com.ddev.site-name=,com.ddev.webtag=v1.25.3,com.docker.compose.project=ddev-router,com.docker.compose.service=ddev-router,maintainer=DDEV <support@ddev.com>","LocalVolumes":"1","Mounts":"ddev-global-ca…","Names":"ddev-router","Networks":"ddev_default","Platform":null,"Ports":"127.0.0.1:80->80/tcp","RunningFor":"2 hours ago","Size":"247kB (virtual 237MB)","State":"running","Status":"Up 2 hours (healthy)"}"#;

    const PLAIN_COMPOSE_PS_LINE: &str = r#"{"Command":"\"docker-entrypoint.s…\"","CreatedAt":"2026-08-11 10:26:07 +0200 CEST","ID":"a3735ec9b445","Image":"postgres:17.10","Labels":"com.docker.compose.config-hash=691a70112b885d00dc7cac0fbe7bafc9112b01cc14981b0889325f5851faba3a,com.docker.compose.container-number=1,com.docker.compose.project=verdi-middleware,com.docker.compose.service=postgres","LocalVolumes":"1","Mounts":"verdi-middlewa…","Names":"verdi-middleware-postgres-1","Networks":"verdi-middleware_default","Platform":null,"Ports":"0.0.0.0:5432->5432/tcp","RunningFor":"26 hours ago","Size":"14.4kB (virtual 476MB)","State":"running","Status":"Up 26 hours"}"#;

    const DDEV_WEB_STATS_LINE: &str = r#"{"BlockIO":"3.34GB / 3.18GB","CPUPerc":"0.02%","Container":"95b1ce6cdd20045b6d64d47f0c6d7052a2900a58bfb39b8a007ae07a36040cf1","ID":"95b1ce6cdd20","MemPerc":"1.74%","MemUsage":"139.6MiB / 7.816GiB","Name":"ddev-pagetree-facets-web","NetIO":"1.05GB / 49.4MB","PIDs":"111"}"#;

    const PLAIN_COMPOSE_STATS_LINE: &str = r#"{"BlockIO":"6.2GB / 51.5MB","CPUPerc":"0.00%","Container":"a3735ec9b44529225a9be3bb8665891b03cbc9f3606e64fd5d5d5a54be5ce56e","ID":"a3735ec9b445","MemPerc":"0.05%","MemUsage":"3.824MiB / 7.816GiB","Name":"verdi-middleware-postgres-1","NetIO":"94.6kB / 60.1kB","PIDs":"6"}"#;

    // Real `docker images --filter dangling=true --format '{{json .}}'`
    // lines captured on a live machine. Note some dangling (untagged)
    // images still have a nonzero Containers count — a stopped or
    // running container still references them, so `docker image prune`
    // would skip them even though they're untagged.
    const DANGLING_UNUSED_LINE: &str = r#"{"Containers":"0","CreatedAt":"2026-08-10 17:03:13 +0200 CEST","CreatedSince":"46 hours ago","Digest":"<none>","ID":"babccc01d2f7","Repository":"<none>","SharedSize":"N/A","Size":"1.76GB","Tag":"<none>","UniqueSize":"N/A"}"#;

    const DANGLING_STILL_REFERENCED_LINE: &str = r#"{"Containers":"1","CreatedAt":"2026-08-05 02:38:39 +0200 CEST","CreatedSince":"7 days ago","Digest":"","ID":"b9982e1879d4","Repository":"postgres","SharedSize":"N/A","Size":"476MB","Tag":"<none>","UniqueSize":"N/A"}"#;

    const DANGLING_UNUSED_LINE_2: &str = r#"{"Containers":"0","CreatedAt":"2026-07-27 13:57:14 +0200 CEST","CreatedSince":"2 weeks ago","Digest":"<none>","ID":"e85909867eea","Repository":"<none>","SharedSize":"N/A","Size":"576MB","Tag":"<none>","UniqueSize":"N/A"}"#;

    #[test]
    fn label_value_extracts_a_present_label() {
        let labels = "com.ddev.platform=ddev,com.ddev.site-name=pagetree-facets,foo=bar";
        assert_eq!(
            label_value(labels, "com.ddev.site-name"),
            Some("pagetree-facets".to_string())
        );
    }

    #[test]
    fn label_value_treats_empty_value_as_absent() {
        let labels = "com.ddev.platform=ddev,com.ddev.site-name=,foo=bar";
        assert_eq!(label_value(labels, "com.ddev.site-name"), None);
    }

    #[test]
    fn label_value_is_none_when_key_missing() {
        let labels = "com.docker.compose.project=verdi-middleware,foo=bar";
        assert_eq!(label_value(labels, "com.ddev.site-name"), None);
    }

    #[test]
    fn parses_docker_size_units() {
        assert_eq!(parse_docker_size("139.6MiB"), Some(mib(139.6)));
        assert_eq!(parse_docker_size("7.816GiB"), Some(gib(7.816)));
        assert_eq!(parse_docker_size("3.824MiB"), Some(mib(3.824)));
        assert_eq!(parse_docker_size("512B"), Some(512));
        assert_eq!(parse_docker_size("not-a-size"), None);
    }

    fn mib(n: f64) -> u64 {
        (n * 1024.0 * 1024.0).round() as u64
    }

    fn gib(n: f64) -> u64 {
        (n * 1024.0 * 1024.0 * 1024.0).round() as u64
    }

    #[test]
    fn parse_ps_line_extracts_ddev_project_from_real_fixture() {
        let entry = parse_ps_line(DDEV_WEB_PS_LINE).unwrap();
        assert_eq!(entry.id, "95b1ce6cdd20");
        assert_eq!(entry.name, "ddev-pagetree-facets-web");
        assert!(entry.ddev_managed);
        assert_eq!(entry.ddev_project, Some("pagetree-facets".to_string()));
        assert_eq!(
            entry.compose_project,
            Some("ddev-pagetree-facets".to_string())
        );
    }

    /// DDEV's own shared infrastructure (router, ssh-agent) is real, but
    /// not tied to any single project — real live bug found: it carries
    /// `com.ddev.platform=ddev` with an EMPTY `com.ddev.site-name`, and
    /// was being misclassified as "running outside DDEV" when only
    /// `ddev_project` (not `ddev_managed`) was checked.
    #[test]
    fn parse_ps_line_treats_ddev_shared_infra_as_ddev_managed_but_projectless() {
        let entry = parse_ps_line(DDEV_ROUTER_PS_LINE).unwrap();
        assert!(entry.ddev_managed);
        assert_eq!(entry.ddev_project, None);
        assert_eq!(entry.compose_project, Some("ddev-router".to_string()));
    }

    #[test]
    fn parse_ps_line_marks_a_plain_compose_container_as_not_ddev_managed() {
        let entry = parse_ps_line(PLAIN_COMPOSE_PS_LINE).unwrap();
        assert_eq!(entry.name, "verdi-middleware-postgres-1");
        assert!(!entry.ddev_managed);
        assert_eq!(entry.ddev_project, None);
        assert_eq!(entry.compose_project, Some("verdi-middleware".to_string()));
    }

    #[test]
    fn parse_ps_rejects_invalid_json() {
        let err = parse_ps_line("not json").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn parse_stats_line_extracts_cpu_and_memory() {
        let entry = parse_stats_line(DDEV_WEB_STATS_LINE).unwrap();
        assert_eq!(entry.id, "95b1ce6cdd20");
        assert_eq!(entry.cpu_percent, 0.02);
        assert_eq!(entry.mem_bytes, mib(139.6));
    }

    #[test]
    fn merge_joins_ps_and_stats_by_id_and_drops_unmatched() {
        let ps = parse_ps(&format!("{DDEV_WEB_PS_LINE}\n{PLAIN_COMPOSE_PS_LINE}\n")).unwrap();
        let stats = parse_stats(DDEV_WEB_STATS_LINE).unwrap();

        let containers = merge(ps, &stats);

        assert_eq!(containers.len(), 1);
        assert_eq!(containers[0].name, "ddev-pagetree-facets-web");
        assert_eq!(containers[0].cpu_percent, 0.02);
    }

    #[test]
    fn merge_includes_all_when_stats_present_for_both() {
        let ps = parse_ps(&format!("{DDEV_WEB_PS_LINE}\n{PLAIN_COMPOSE_PS_LINE}\n")).unwrap();
        let stats = parse_stats(&format!(
            "{DDEV_WEB_STATS_LINE}\n{PLAIN_COMPOSE_STATS_LINE}\n"
        ))
        .unwrap();

        let containers = merge(ps, &stats);

        assert_eq!(containers.len(), 2);
        let unmanaged = containers
            .iter()
            .find(|c| c.name.starts_with("verdi"))
            .unwrap();
        assert_eq!(unmanaged.ddev_project, None);
        assert_eq!(
            unmanaged.compose_project,
            Some("verdi-middleware".to_string())
        );
    }

    #[test]
    fn parses_image_size_units() {
        assert_eq!(parse_image_size("1.76GB"), Some(gb(1.76)));
        assert_eq!(parse_image_size("476MB"), Some(mb(476.0)));
        assert_eq!(parse_image_size("512B"), Some(512));
        assert_eq!(parse_image_size("not-a-size"), None);
    }

    fn mb(n: f64) -> u64 {
        (n * 1024.0 * 1024.0).round() as u64
    }

    fn gb(n: f64) -> u64 {
        (n * 1024.0 * 1024.0 * 1024.0).round() as u64
    }

    #[test]
    fn parse_dangling_image_line_extracts_containers_and_size() {
        let entry = parse_dangling_image_line(DANGLING_UNUSED_LINE).unwrap();
        assert_eq!(entry.containers, "0");
        assert_eq!(entry.size_bytes, gb(1.76));
    }

    #[test]
    fn parse_dangling_image_line_rejects_invalid_json() {
        let err = parse_dangling_image_line("not json").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn parse_dangling_images_only_counts_unreferenced_images() {
        let raw = format!(
            "{DANGLING_UNUSED_LINE}\n{DANGLING_STILL_REFERENCED_LINE}\n{DANGLING_UNUSED_LINE_2}\n"
        );
        let result = parse_dangling_images(&raw).unwrap();

        // The 476MB entry has Containers: "1" — still referenced, so
        // `docker image prune` would skip it. Only the two 0-container
        // entries should count toward the reclaimable total.
        assert_eq!(result.count, 2);
        assert_eq!(result.reclaimable_bytes, gb(1.76) + mb(576.0));
    }

    #[test]
    fn parse_dangling_images_of_empty_output_is_zero() {
        let result = parse_dangling_images("").unwrap();
        assert_eq!(result, DanglingImages::default());
    }
}
