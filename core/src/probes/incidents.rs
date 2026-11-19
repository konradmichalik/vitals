//! JetsamEvent reports → what macOS ended when memory ran out.
//!
//! When memory pressure cannot be relieved otherwise, the kernel's jetsam
//! mechanism terminates processes and `osanalyticshelper` writes a
//! `JetsamEvent-<date>.ips` report to `/Library/Logs/DiagnosticReports`.
//! The file is two JSON documents: a one-line header (`bug_type` "298")
//! and the body with `largestProcess`, the page size and a `processes`
//! array. Only the process that was terminated carries a `reason` key
//! (Apple, "Identifying high-memory use with jetsam event reports").
//! Memory per process is `rpages` × page size. On newer systems the page
//! size sits in `memoryStatus.pageSize`, older ones also have a top-level
//! `pageSize`; both are accepted.
//!
//! The directory may not be readable for every user; that degrades to
//! "no incidents", never an error.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::SystemTime;

use serde_json::Value;

use crate::types::{Incident, IncidentProcess};

const DIRECTORIES: &[&str] = &["/Library/Logs/DiagnosticReports"];
const TOP_PROCESSES: usize = 5;

pub fn recent(max_age_days: u64, limit: usize, now: SystemTime) -> Vec<Incident> {
    let mut dirs: Vec<PathBuf> = DIRECTORIES.iter().map(PathBuf::from).collect();
    if let Ok(home) = std::env::var("HOME") {
        dirs.push(PathBuf::from(home).join("Library/Logs/DiagnosticReports"));
    }

    let max_age = std::time::Duration::from_secs(max_age_days * 86400);
    let mut files: Vec<(SystemTime, PathBuf)> = dirs
        .iter()
        .filter_map(|dir| std::fs::read_dir(dir).ok())
        .flatten()
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| is_jetsam_report(path))
        .filter_map(|path| Some((std::fs::metadata(&path).ok()?.modified().ok()?, path)))
        .filter(|(mtime, _)| {
            now.duration_since(*mtime)
                .map_or(true, |age| age <= max_age)
        })
        .collect();
    files.sort_by_key(|a| std::cmp::Reverse(a.0));
    files.dedup_by(|a, b| a.1.file_name() == b.1.file_name());

    files
        .into_iter()
        .take(limit)
        .filter_map(|(mtime, path)| cached_parse(&path, mtime))
        .collect()
}

type Cache = HashMap<PathBuf, (SystemTime, Option<Incident>)>;

/// Reports are written once and never change, but the menubar app polls
/// every few seconds and a report lists every process on the machine.
/// Parsing each file once per process lifetime keeps polling cheap.
fn cached_parse(path: &Path, mtime: SystemTime) -> Option<Incident> {
    static CACHE: OnceLock<Mutex<Cache>> = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    if let Ok(guard) = cache.lock() {
        if let Some((cached_mtime, incident)) = guard.get(path) {
            if *cached_mtime == mtime {
                return incident.clone();
            }
        }
    }
    let incident = std::fs::read_to_string(path)
        .ok()
        .and_then(|raw| parse(&raw, &path.file_name()?.to_string_lossy()));
    if let Ok(mut guard) = cache.lock() {
        guard.insert(path.to_path_buf(), (mtime, incident.clone()));
    }
    incident
}

fn is_jetsam_report(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with("JetsamEvent-") && name.ends_with(".ips"))
}

pub(crate) fn parse(raw: &str, file_name: &str) -> Option<Incident> {
    let mut stream = serde_json::Deserializer::from_str(raw).into_iter::<Value>();
    let first = stream.next()?.ok()?;
    // Older reports are a single document; the usual form is header + body.
    let (header, body) = match stream.next() {
        Some(Ok(body)) => (first, body),
        _ => (Value::Null, first),
    };
    if let Some(bug_type) = header.get("bug_type").and_then(Value::as_str) {
        if bug_type != "298" {
            return None;
        }
    }

    let page_size = body
        .get("memoryStatus")
        .and_then(|m| m.get("pageSize"))
        .or_else(|| body.get("pageSize"))
        .and_then(Value::as_u64)
        .unwrap_or(16_384);

    let date = body
        .get("date")
        .or_else(|| header.get("timestamp"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();

    let mut processes: Vec<IncidentProcess> = body
        .get("processes")
        .and_then(Value::as_array)
        .map(|list| list.iter().filter_map(|p| process(p, page_size)).collect())
        .unwrap_or_default();
    processes.sort_by_key(|a| std::cmp::Reverse(a.bytes));

    let killed: Vec<IncidentProcess> = processes
        .iter()
        .filter(|p| p.reason.is_some())
        .cloned()
        .collect();
    let top: Vec<IncidentProcess> = processes.into_iter().take(TOP_PROCESSES).collect();

    Some(Incident {
        file: file_name.to_string(),
        date,
        largest_process: body
            .get("largestProcess")
            .and_then(Value::as_str)
            .map(display_name),
        page_size_bytes: page_size,
        killed,
        top,
    })
}

fn process(value: &Value, page_size: u64) -> Option<IncidentProcess> {
    let name = value.get("name").and_then(Value::as_str)?;
    let rpages = value.get("rpages").and_then(Value::as_u64).unwrap_or(0);
    Some(IncidentProcess {
        pid: value.get("pid").and_then(Value::as_u64).map(|p| p as u32),
        name: display_name(name),
        bytes: rpages * page_size,
        reason: value
            .get("reason")
            .and_then(Value::as_str)
            .map(str::to_string),
    })
}

/// The Claude Code CLI names its process after its version number
/// (`2.1.228`), which is also what jetsam records. Spelled out here so an
/// incident does not just say "2.1.7".
fn display_name(name: &str) -> String {
    let is_version = {
        let parts: Vec<&str> = name.split('.').collect();
        parts.len() == 3
            && parts
                .iter()
                .all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
    };
    if is_version {
        format!("Claude Code {name}")
    } else {
        name.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MODERN: &str = r#"{"bug_type":"298","timestamp":"2026-01-15 18:22:49.00 +0100","os_version":"macOS 15.7 (24G207)"}
{
  "date" : "2026-01-15 18:22:49.12 +0100",
  "largestProcess" : "2.1.7",
  "memoryStatus" : { "pageSize" : 16384 },
  "processes" : [
    { "pid" : 10652, "name" : "2.1.7", "rpages" : 977907, "cpuTime" : 1805.89 },
    { "pid" : 11129, "name" : "2.1.7", "rpages" : 950678, "reason" : "vm-pageshortage" },
    { "pid" : 501, "name" : "phpstorm", "rpages" : 200000 },
    { "pid" : 77, "name" : "mds_stores", "rpages" : 1000, "reason" : "highwater" }
  ]
}"#;

    #[test]
    fn reads_largest_process_page_size_and_killed_processes() {
        let incident = parse(MODERN, "JetsamEvent-2026-01-15-182249.ips").unwrap();
        assert_eq!(
            incident.largest_process.as_deref(),
            Some("Claude Code 2.1.7")
        );
        assert_eq!(incident.page_size_bytes, 16384);
        assert_eq!(incident.date, "2026-01-15 18:22:49.12 +0100");
        assert_eq!(incident.killed.len(), 2);
        assert_eq!(incident.killed[0].bytes, 950_678 * 16_384);
        assert_eq!(
            incident.killed[0].reason.as_deref(),
            Some("vm-pageshortage")
        );
        assert_eq!(incident.top[0].pid, Some(10652));
        assert_eq!(incident.top.len(), 4);
    }

    /// The 2017 iOS sample has the page size only inside memoryStatus and
    /// no reason anywhere; the format is the same family.
    #[test]
    fn falls_back_to_top_level_page_size_and_tolerates_no_killed_process() {
        let raw = r#"{"bug_type":"298","timestamp":"2017-05-03 08:41:25.25 +1000"}
{"date":"2017-05-03 08:41:25.25 +1000","pageSize":4096,"largestProcess":"com.apple.WebKit.WebContent","processes":[{"name":"a","rpages":10}]}"#;
        let incident = parse(raw, "JetsamEvent-x.ips").unwrap();
        assert_eq!(incident.page_size_bytes, 4096);
        assert_eq!(incident.top[0].bytes, 40_960);
        assert!(incident.killed.is_empty());
    }

    #[test]
    fn rejects_other_report_types_and_garbage() {
        assert!(parse(
            r#"{"bug_type":"309"}
{"processes":[]}"#,
            "x.ips"
        )
        .is_none());
        assert!(parse("not json", "x.ips").is_none());
    }

    #[test]
    fn recognises_report_file_names() {
        assert!(is_jetsam_report(Path::new(
            "/x/JetsamEvent-2026-01-15-182249.ips"
        )));
        assert!(!is_jetsam_report(Path::new("/x/PhpStorm-2026-01-15.ips")));
    }
}
