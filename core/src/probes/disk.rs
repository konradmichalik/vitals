//! `iostat -d -I` → total megabytes transferred by all disks since boot.
//!
//! With `-I`, macOS `iostat` prints totals instead of per-second averages:
//! `KB/t`, `xfrs` and `MB` per device (iostat(8)). A rate needs two
//! readings, so this only reports the running total; callers that poll
//! (the menubar app) derive MB/s from the difference between samples.

use crate::error::VitalsError;

const COMMAND: &str = "iostat -d -I -c 1";

pub fn total_bytes() -> Result<u64, VitalsError> {
    let raw = super::shell::run("iostat", &["-d", "-I", "-c", "1"])?;
    parse(&raw)
}

/// Header lines: device names, then `KB/t xfrs MB` repeated per device.
/// The data line holds the same triple per device; the third value of
/// each triple is the device's total in MB.
fn parse(raw: &str) -> Result<u64, VitalsError> {
    let data = raw
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .find(|line| line.split_whitespace().all(|t| t.parse::<f64>().is_ok()))
        .ok_or_else(|| VitalsError::parse(COMMAND, "no numeric data line"))?;

    let values: Vec<f64> = data
        .split_whitespace()
        .filter_map(|t| t.parse::<f64>().ok())
        .collect();
    if values.is_empty() || !values.len().is_multiple_of(3) {
        return Err(VitalsError::parse(
            COMMAND,
            format!("expected KB/t xfrs MB triples, got {} values", values.len()),
        ));
    }

    let megabytes: f64 = values.chunks(3).map(|triple| triple[2]).sum();
    Ok((megabytes * 1024.0 * 1024.0).round() as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sums_the_mb_column_of_every_device() {
        let raw = "              disk0               disk4 \n    KB/t  xfrs   MB     KB/t  xfrs   MB \n   26.33 1234567 31745.47   64.00  100  6.25 \n";
        let bytes = parse(raw).unwrap();
        assert_eq!(
            bytes,
            ((31745.47 + 6.25) * 1024.0 * 1024.0_f64).round() as u64
        );
    }

    #[test]
    fn single_device() {
        let raw = "              disk0 \n    KB/t  xfrs   MB \n   20.00  10  1.00 \n";
        assert_eq!(parse(raw).unwrap(), 1024 * 1024);
    }

    #[test]
    fn rejects_output_without_data() {
        assert!(parse("              disk0 \n    KB/t  xfrs   MB \n").is_err());
    }
}
