//! `memory_pressure` / `sysctl kern.memorystatus_vm_pressure_level` →
//! pressure level. High "memory used" is normal on macOS (free RAM doubles
//! as file cache) — pressure level is the actual scarcity signal, not
//! free percent alone (§7).

use crate::error::VitalsError;
use crate::types::PressureLevel;

pub fn pressure_level() -> Result<PressureLevel, VitalsError> {
    let raw = super::shell::run("sysctl", &["-n", "kern.memorystatus_vm_pressure_level"])?;
    parse(&raw)
}

pub fn total_bytes() -> Result<u64, VitalsError> {
    let raw = super::shell::run("sysctl", &["-n", "hw.memsize"])?;
    parse_total_bytes(&raw)
}

fn parse_total_bytes(raw: &str) -> Result<u64, VitalsError> {
    raw.trim().parse::<u64>().map_err(|_| {
        VitalsError::parse(
            "sysctl -n hw.memsize",
            format!("`{}` is not a byte count", raw.trim()),
        )
    })
}

fn parse(raw: &str) -> Result<PressureLevel, VitalsError> {
    const COMMAND: &str = "sysctl -n kern.memorystatus_vm_pressure_level";

    let value: u8 = raw
        .trim()
        .parse()
        .map_err(|_| VitalsError::parse(COMMAND, format!("`{}` is not a number", raw.trim())))?;

    match value {
        1 => Ok(PressureLevel::Normal),
        2 => Ok(PressureLevel::Warn),
        4 => Ok(PressureLevel::Critical),
        other => Err(VitalsError::parse(
            COMMAND,
            format!("unexpected pressure level value `{other}`"),
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_warn() {
        assert_eq!(parse("2\n").unwrap(), PressureLevel::Warn);
    }

    #[test]
    fn parses_normal() {
        assert_eq!(parse("1\n").unwrap(), PressureLevel::Normal);
    }

    #[test]
    fn parses_critical() {
        assert_eq!(parse("4\n").unwrap(), PressureLevel::Critical);
    }

    #[test]
    fn rejects_unknown_value() {
        let err = parse("7\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn rejects_non_numeric_value() {
        let err = parse("banana\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn parses_total_bytes() {
        assert_eq!(parse_total_bytes("25769803776\n").unwrap(), 25_769_803_776);
    }

    #[test]
    fn rejects_non_numeric_total_bytes() {
        let err = parse_total_bytes("banana\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }
}
