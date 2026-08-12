//! `ps -eo pid,ppid,etime,%cpu,rss,comm,command` → the raw process table
//! that classification (Claude sessions, ACP agents, OrbStack, …) is
//! built on top of.
//!
//! Match on `comm` (the resolved executable path), never on `command` or
//! basename: Claude Code sets argv to plain `claude` with no version path,
//! and Warp's binary is literally named `stable` (§7). `%cpu` from `ps` is
//! a lifetime average, not instantaneous — diff two reads for "is this
//! spinning right now".

use crate::error::VitalsError;

type ProcessRow = (u32, u32, u64, f64, u64, String);

#[derive(Debug, Clone)]
pub struct ProcessEntry {
    pub pid: u32,
    pub ppid: u32,
    pub etime_seconds: u64,
    pub cpu_percent: f64,
    pub rss_bytes: u64,
    pub comm: String,
    pub command: String,
}

pub fn list() -> Result<Vec<ProcessEntry>, VitalsError> {
    let table_raw = super::shell::run("ps", &["-eo", "pid,ppid,etime,%cpu,rss,command"])?;
    let comm_raw = super::shell::run("ps", &["-eo", "pid=,comm="])?;
    let comm_map = parse_comm_map(&comm_raw)?;

    Ok(parse_table(&table_raw)?
        .into_iter()
        .filter_map(
            |(pid, ppid, etime_seconds, cpu_percent, rss_bytes, command)| {
                comm_map.get(&pid).map(|comm| ProcessEntry {
                    pid,
                    ppid,
                    etime_seconds,
                    cpu_percent,
                    rss_bytes,
                    comm: comm.clone(),
                    command,
                })
            },
        )
        .collect())
}

const TABLE_COMMAND: &str = "ps -eo pid,ppid,etime,%cpu,rss,command";
const COMM_COMMAND: &str = "ps -eo pid=,comm=";

fn parse_etime(raw: &str) -> Result<u64, VitalsError> {
    let parse_error = || VitalsError::parse(TABLE_COMMAND, format!("`{raw}` is not a valid etime"));

    let (days, rest) = match raw.split_once('-') {
        Some((days, rest)) => (days.parse::<u64>().map_err(|_| parse_error())?, rest),
        None => (0, raw),
    };

    let parts: Vec<&str> = rest.split(':').collect();
    let (hours, minutes, seconds) = match parts[..] {
        [h, m, s] => (
            h.parse::<u64>().map_err(|_| parse_error())?,
            m.parse::<u64>().map_err(|_| parse_error())?,
            s.parse::<u64>().map_err(|_| parse_error())?,
        ),
        [m, s] => (
            0,
            m.parse::<u64>().map_err(|_| parse_error())?,
            s.parse::<u64>().map_err(|_| parse_error())?,
        ),
        _ => return Err(parse_error()),
    };

    Ok(days * 86400 + hours * 3600 + minutes * 60 + seconds)
}

fn parse_table(raw: &str) -> Result<Vec<ProcessRow>, VitalsError> {
    let mut saw_data_line = false;
    let mut rows = Vec::new();

    for line in raw.lines().skip(1) {
        if line.trim().is_empty() {
            continue;
        }
        saw_data_line = true;

        if let Some(row) = parse_table_line(line) {
            rows.push(row);
        }
    }

    if rows.is_empty() && saw_data_line {
        return Err(VitalsError::parse(
            TABLE_COMMAND,
            "no data lines matched the expected pid ppid etime %cpu rss command format",
        ));
    }

    Ok(rows)
}

fn parse_table_line(line: &str) -> Option<ProcessRow> {
    let mut rest = line.trim_start();
    let mut tokens = Vec::with_capacity(5);

    for _ in 0..5 {
        let token_end = rest.find(char::is_whitespace)?;
        tokens.push(&rest[..token_end]);
        rest = rest[token_end..].trim_start();
    }

    if rest.is_empty() {
        return None;
    }

    let pid = tokens[0].parse::<u32>().ok()?;
    let ppid = tokens[1].parse::<u32>().ok()?;
    let etime_seconds = parse_etime(tokens[2]).ok()?;
    let cpu_percent = tokens[3].parse::<f64>().ok()?;
    let rss_bytes = tokens[4].parse::<u64>().ok()? * 1024;

    Some((
        pid,
        ppid,
        etime_seconds,
        cpu_percent,
        rss_bytes,
        rest.to_string(),
    ))
}

fn parse_comm_map(raw: &str) -> Result<std::collections::HashMap<u32, String>, VitalsError> {
    let mut saw_data_line = false;
    let mut map = std::collections::HashMap::new();

    for line in raw.lines() {
        if line.trim().is_empty() {
            continue;
        }
        saw_data_line = true;

        let trimmed = line.trim_start();
        if let Some(token_end) = trimmed.find(char::is_whitespace) {
            let pid = trimmed[..token_end].parse::<u32>().ok();
            let comm = trimmed[token_end..].trim();
            if let (Some(pid), false) = (pid, comm.is_empty()) {
                map.insert(pid, comm.to_string());
            }
        }
    }

    if map.is_empty() && saw_data_line {
        return Err(VitalsError::parse(
            COMM_COMMAND,
            "no data lines matched the expected pid comm format",
        ));
    }

    Ok(map)
}

#[cfg(test)]
mod tests {
    use super::*;

    const TABLE_FIXTURE: &str = "  PID  PPID     ELAPSED  %CPU    RSS COMMAND\n    1     0 13-23:37:05   0.1  19696 /sbin/launchd\n  311     1    20:57:48   0.0   9344 /System/Library/PrivateFrameworks/HearingCore.framework/heard\n";

    const COMM_FIXTURE: &str = "    1 /sbin/launchd\n  311 /System/Library/PrivateFrameworks/HearingCore.framework/heard\n";

    #[test]
    fn parse_etime_handles_hh_mm_ss() {
        assert_eq!(parse_etime("20:57:48").unwrap(), 20 * 3600 + 57 * 60 + 48);
    }

    #[test]
    fn parse_etime_handles_dd_hh_mm_ss() {
        assert_eq!(
            parse_etime("13-23:37:05").unwrap(),
            13 * 86400 + 23 * 3600 + 37 * 60 + 5
        );
    }

    #[test]
    fn parse_etime_handles_mm_ss() {
        assert_eq!(parse_etime("05:23").unwrap(), 5 * 60 + 23);
    }

    #[test]
    fn parse_etime_rejects_garbage() {
        let err = parse_etime("garbage").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn parse_table_parses_fixture_rows() {
        let rows = parse_table(TABLE_FIXTURE).unwrap();
        assert_eq!(rows.len(), 2);

        let launchd = &rows[0];
        assert_eq!(launchd.0, 1);
        assert_eq!(launchd.1, 0);
        assert_eq!(launchd.2, 13 * 86400 + 23 * 3600 + 37 * 60 + 5);
        assert_eq!(launchd.3, 0.1);
        assert_eq!(launchd.4, 19696 * 1024);
        assert_eq!(launchd.5, "/sbin/launchd");

        let hearing_core = &rows[1];
        assert_eq!(hearing_core.0, 311);
        assert_eq!(hearing_core.1, 1);
        assert_eq!(hearing_core.2, 20 * 3600 + 57 * 60 + 48);
        assert_eq!(hearing_core.3, 0.0);
        assert_eq!(hearing_core.4, 9344 * 1024);
        assert_eq!(
            hearing_core.5,
            "/System/Library/PrivateFrameworks/HearingCore.framework/heard"
        );
    }

    #[test]
    fn parse_table_preserves_internal_spaces_in_command() {
        let raw = "  PID  PPID     ELAPSED  %CPU    RSS COMMAND\n 500   1    00:05:00   1.5   2048 /Applications/Foo Bar.app/Contents/MacOS/Foo Bar --flag\n";
        let rows = parse_table(raw).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(
            rows[0].5,
            "/Applications/Foo Bar.app/Contents/MacOS/Foo Bar --flag"
        );
    }

    #[test]
    fn parse_comm_map_parses_fixture() {
        let map = parse_comm_map(COMM_FIXTURE).unwrap();
        assert_eq!(map.get(&1).map(String::as_str), Some("/sbin/launchd"));
        assert_eq!(
            map.get(&311).map(String::as_str),
            Some("/System/Library/PrivateFrameworks/HearingCore.framework/heard")
        );
    }
}
