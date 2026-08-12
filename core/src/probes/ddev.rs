//! `ddev list --json-output` → per-project name, status, location.
//!
//! DDEV may not be installed or on PATH — callers must degrade gracefully
//! rather than treating that as a hard error (§7). Given a longer timeout
//! than other probes since it queries Docker per project — but still a
//! bounded one: `ddev list` was observed hanging for minutes when OrbStack
//! stalled, and a monitoring tool that can hang forever is broken by
//! design.

use std::time::Duration;

use crate::error::VitalsError;

const TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Debug, Clone)]
pub struct DdevProject {
    pub name: String,
    pub status: String,
    pub location: String,
}

pub fn list() -> Result<Vec<DdevProject>, VitalsError> {
    match super::shell::run_with_timeout("ddev", &["list", "--json-output"], TIMEOUT) {
        Ok(raw) => parse(&raw),
        Err(VitalsError::CommandFailed { source, .. })
            if source.kind() == std::io::ErrorKind::NotFound =>
        {
            Ok(Vec::new())
        }
        Err(err) => Err(err),
    }
}

const COMMAND: &str = "ddev list --json-output";

fn parse(raw: &str) -> Result<Vec<DdevProject>, VitalsError> {
    let envelope: serde_json::Value = serde_json::from_str(raw)
        .map_err(|source| VitalsError::parse(COMMAND, source.to_string()))?;

    let entries = envelope
        .get("raw")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| VitalsError::parse(COMMAND, "missing \"raw\" array"))?;

    entries
        .iter()
        .map(|entry| {
            let name = field(entry, "name")?;
            let status = field(entry, "status")?;
            let location = field(entry, "approot")?;

            Ok(DdevProject {
                name,
                status,
                location,
            })
        })
        .collect()
}

fn field(entry: &serde_json::Value, key: &str) -> Result<String, VitalsError> {
    entry
        .get(key)
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| {
            VitalsError::parse(COMMAND, format!("missing or non-string \"{key}\" field"))
        })
}

pub fn summarize(projects: &[DdevProject]) -> crate::types::DdevInfo {
    let mut info = crate::types::DdevInfo::default();

    for project in projects {
        match project.status.as_str() {
            "running" => info.running.push(project.name.clone()),
            "stopped" => info.stopped_count += 1,
            "paused" => info.paused_count += 1,
            _ => info.problems.push(project.name.clone()),
        }
    }

    info
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = r#"{"level":"info","msg":"...(ignore)...","raw":[{"name":"ikkbb-website","status":"running","approot":"/Users/k.michalik/Sites/Projects/ikkbb","docroot":"web/public","other_field":"ignore me"},{"name":"pagetree-facets","status":"running","approot":"/Users/k.michalik/Sites/Packages/typo3-pagetree-facets"},{"name":"witte","status":"stopped","approot":"/Users/k.michalik/Sites/Projects/witte"}],"time":"2026-08-12T10:58:06+02:00"}"#;

    #[test]
    fn parse_extracts_projects_from_raw_array() {
        let projects = parse(FIXTURE).unwrap();

        assert_eq!(projects.len(), 3);
        assert_eq!(projects[0].name, "ikkbb-website");
        assert_eq!(projects[0].status, "running");
        assert_eq!(
            projects[0].location,
            "/Users/k.michalik/Sites/Projects/ikkbb"
        );
        assert_eq!(projects[2].name, "witte");
        assert_eq!(projects[2].status, "stopped");
        assert_eq!(
            projects[2].location,
            "/Users/k.michalik/Sites/Projects/witte"
        );
    }

    #[test]
    fn parse_rejects_invalid_json() {
        let result = parse("not json");

        assert!(matches!(result, Err(VitalsError::ParseError { .. })));
    }

    #[test]
    fn summarize_buckets_projects_by_status() {
        let projects = vec![
            DdevProject {
                name: "running-one".to_string(),
                status: "running".to_string(),
                location: "/tmp/running-one".to_string(),
            },
            DdevProject {
                name: "stopped-one".to_string(),
                status: "stopped".to_string(),
                location: "/tmp/stopped-one".to_string(),
            },
            DdevProject {
                name: "restarting-one".to_string(),
                status: "restarting".to_string(),
                location: "/tmp/restarting-one".to_string(),
            },
        ];

        let info = summarize(&projects);

        assert_eq!(info.running, vec!["running-one".to_string()]);
        assert_eq!(info.stopped_count, 1);
        assert_eq!(info.paused_count, 0);
        assert_eq!(info.problems, vec!["restarting-one".to_string()]);
    }
}
