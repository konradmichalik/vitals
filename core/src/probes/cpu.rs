//! `top -l 1 -n 0` → aggregate CPU usage. Unlike `ps`'s per-process
//! `%CPU` (a lifetime average), `top -l 1` samples system-wide usage over
//! its own brief internal window — a single shot already reflects
//! current load, no before/after diffing needed on our end.

use crate::error::VitalsError;
use crate::types::CpuUsage;

pub fn read() -> Result<CpuUsage, VitalsError> {
    let raw = super::shell::run("top", &["-l", "1", "-n", "0"])?;
    parse(&raw)
}

fn parse(raw: &str) -> Result<CpuUsage, VitalsError> {
    const COMMAND: &str = "top -l 1 -n 0";
    let parse_error = |reason: &str| VitalsError::parse(COMMAND, reason);

    let line = raw
        .lines()
        .find(|line| line.starts_with("CPU usage:"))
        .ok_or_else(|| parse_error("no `CPU usage:` line found"))?;

    let mut user = None;
    let mut system = None;
    let mut idle = None;

    for part in line.trim_start_matches("CPU usage:").split(',') {
        let part = part.trim();
        let Some(value) = part
            .split('%')
            .next()
            .and_then(|v| v.trim().parse::<f64>().ok())
        else {
            continue;
        };
        if part.contains("user") {
            user = Some(value);
        } else if part.contains("sys") {
            system = Some(value);
        } else if part.contains("idle") {
            idle = Some(value);
        }
    }

    Ok(CpuUsage {
        user_percent: user.ok_or_else(|| parse_error("missing user percent"))?,
        system_percent: system.ok_or_else(|| parse_error("missing sys percent"))?,
        idle_percent: idle.ok_or_else(|| parse_error("missing idle percent"))?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = "Processes: 951 total, 17 running, 934 sleeping, 8314 threads \n\
2026/08/12 19:16:15\n\
Load Avg: 13.01, 13.64, 13.40 \n\
CPU usage: 22.82% user, 22.93% sys, 54.23% idle \n\
SharedLibs: 424M resident, 80M data, 110M linkedit.\n\
MemRegions: 813059 total, 3458M resident, 107M private, 3526M shared.\n\
PhysMem: 23G used (6161M wired, 10G compressor), 118M unused.\n\
VM: 435T vsize, 6144M framework vsize, 361798859(0) swapins, 381155633(0) swapouts.\n\
Networks: packets: 642414463/253G in, 613443871/227G out.\n\
Disks: 834572745/14T read, 863516721/11T written.\n";

    #[test]
    fn parses_cpu_usage_from_real_fixture() {
        let usage = parse(FIXTURE).unwrap();
        assert_eq!(usage.user_percent, 22.82);
        assert_eq!(usage.system_percent, 22.93);
        assert_eq!(usage.idle_percent, 54.23);
    }

    #[test]
    fn parses_single_digit_decimal_percent() {
        let usage = parse("CPU usage: 5.0% user, 1.0% sys, 94.0% idle\n").unwrap();
        assert_eq!(usage.user_percent, 5.0);
    }

    #[test]
    fn rejects_output_missing_the_cpu_usage_line() {
        let err = parse("Processes: 5 total\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }
}
