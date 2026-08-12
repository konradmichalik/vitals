//! `sysctl -n kern.boottime` → seconds since boot.

use std::time::{SystemTime, UNIX_EPOCH};

use crate::error::VitalsError;

pub fn seconds() -> Result<u64, VitalsError> {
    let raw = super::shell::run("sysctl", &["-n", "kern.boottime"])?;
    let boot_epoch = parse_boot_epoch(&raw)?;
    let now_epoch = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is before the Unix epoch")
        .as_secs();

    Ok(elapsed_seconds(boot_epoch, now_epoch))
}

fn parse_boot_epoch(raw: &str) -> Result<u64, VitalsError> {
    raw.split_once("sec = ")
        .and_then(|(_, rest)| rest.split(&[',', '}'][..]).next())
        .and_then(|sec| sec.trim().parse::<u64>().ok())
        .ok_or_else(|| {
            VitalsError::parse(
                "sysctl -n kern.boottime",
                format!("no `sec = <n>` field found in `{}`", raw.trim()),
            )
        })
}

fn elapsed_seconds(boot_epoch: u64, now_epoch: u64) -> u64 {
    now_epoch.saturating_sub(boot_epoch)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_real_sysctl_output() {
        let epoch =
            parse_boot_epoch("{ sec = 1785316994, usec = 936157 } Wed Jul 29 11:23:14 2026\n")
                .unwrap();
        assert_eq!(epoch, 1785316994);
    }

    #[test]
    fn rejects_output_without_sec_field() {
        let err = parse_boot_epoch("garbage\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn computes_elapsed_seconds() {
        assert_eq!(elapsed_seconds(100, 150), 50);
    }

    #[test]
    fn saturates_on_clock_skew() {
        assert_eq!(elapsed_seconds(150, 100), 0);
    }
}
