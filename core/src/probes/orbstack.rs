//! `ps` on every OrbStack.app process, aggregated → total CPU %, total RSS.
//!
//! Matched by full executable path (`/OrbStack.app/`), never by basename
//! alone. OrbStack runs as several processes (a GUI shell plus the actual
//! VM/container runtime helpers) — summing across all of them is what
//! `container_load`'s `orbstack_cpu_percent` threshold actually means by
//! "aggregate CPU" (see config.rs), and it's what makes this figure agree
//! with the CPU-heavy OrbStack process `top_processes` independently
//! ranks. Returning just the first match picked an arbitrary single
//! process instead — usually the idle GUI shell, while the real load sat
//! on a different PID entirely.

use crate::error::VitalsError;
use crate::types::OrbstackProcess;

pub fn find() -> Result<Option<OrbstackProcess>, VitalsError> {
    let raw = super::shell::run("ps", &["-eo", "pid,%cpu,rss,comm"])?;
    parse(&raw)
}

fn parse(raw: &str) -> Result<Option<OrbstackProcess>, VitalsError> {
    let mut aggregate: Option<OrbstackProcess> = None;

    for line in raw.lines().skip(1) {
        let fields: Vec<&str> = line.split_whitespace().collect();
        let [pid, cpu_percent, rss_kb, comm] = fields[..] else {
            continue;
        };

        if !comm.contains("/OrbStack.app/") {
            continue;
        }

        let (Ok(pid), Ok(cpu_percent), Ok(rss_kb)) = (
            pid.parse::<u32>(),
            cpu_percent.parse::<f64>(),
            rss_kb.parse::<u64>(),
        ) else {
            continue;
        };
        let rss_bytes = rss_kb * 1024;

        aggregate = Some(match aggregate {
            None => OrbstackProcess {
                pid,
                cpu_percent,
                rss_bytes,
            },
            // The busiest PID becomes the representative one — it's the
            // process someone inspecting this field would actually want
            // to look at — while CPU and RSS keep accumulating.
            Some(existing) => OrbstackProcess {
                pid: if cpu_percent > existing.cpu_percent {
                    pid
                } else {
                    existing.pid
                },
                cpu_percent: existing.cpu_percent + cpu_percent,
                rss_bytes: existing.rss_bytes + rss_bytes,
            },
        });
    }

    Ok(aggregate)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_orbstack_process_by_path() {
        let raw = "  PID %CPU    RSS COMM\n\
                    28016 437.7 7157616 /Applications/OrbStack.app/Contents/MacOS/OrbStack\n\
                      412   0.1   4096 /usr/libexec/logd\n";

        let process = parse(raw).unwrap().unwrap();

        assert_eq!(process.pid, 28016);
        assert_eq!(process.cpu_percent, 437.7);
        assert_eq!(process.rss_bytes, 7_157_616 * 1024);
    }

    #[test]
    fn aggregates_cpu_and_rss_across_multiple_orbstack_processes() {
        let raw = "  PID %CPU    RSS COMM\n\
                    28016   0.3 7157616 /Applications/OrbStack.app/Contents/MacOS/OrbStack\n\
                    28020 195.0 1048576 /Applications/OrbStack.app/Contents/Frameworks/OrbStackHelper\n\
                      412   0.1    4096 /usr/libexec/logd\n";

        let process = parse(raw).unwrap().unwrap();

        // The busiest PID (the helper actually burning CPU) is kept as
        // the representative one, not the first-seen GUI shell.
        assert_eq!(process.pid, 28020);
        assert_eq!(process.cpu_percent, 195.3);
        assert_eq!(process.rss_bytes, (7_157_616 + 1_048_576) * 1024);
    }

    #[test]
    fn returns_none_when_orbstack_not_running() {
        let raw = "  PID %CPU    RSS COMM\n\
                      412   0.1   4096 /usr/libexec/logd\n";

        assert!(parse(raw).unwrap().is_none());
    }

    #[test]
    fn skips_malformed_lines_and_still_finds_match() {
        let raw = "  PID %CPU    RSS COMM\n\
                    not a valid line at all\n\
                    28016 437.7 7157616 /Applications/OrbStack.app/Contents/MacOS/OrbStack\n";

        let process = parse(raw).unwrap().unwrap();

        assert_eq!(process.pid, 28016);
    }
}
