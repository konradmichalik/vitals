//! `ps` on the OrbStack helper PID → CPU %, RSS.
//!
//! Matched by full executable path (`/OrbStack.app/`), never by basename alone.

use crate::error::VitalsError;
use crate::types::OrbstackProcess;

pub fn find() -> Result<Option<OrbstackProcess>, VitalsError> {
    let raw = super::shell::run("ps", &["-eo", "pid,%cpu,rss,comm"])?;
    parse(&raw)
}

fn parse(raw: &str) -> Result<Option<OrbstackProcess>, VitalsError> {
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

        return Ok(Some(OrbstackProcess {
            pid,
            cpu_percent,
            rss_bytes: rss_kb * 1024,
        }));
    }

    Ok(None)
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
