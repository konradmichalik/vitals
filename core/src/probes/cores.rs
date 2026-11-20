//! `sysctl -n hw.perflevel0.logicalcpu hw.perflevel1.logicalcpu` → P-cores
//! and E-cores, kept separate (see §7: compare load against P-core count,
//! not total cores, for the warning threshold).

use crate::error::VitalsError;
use crate::types::CoreCount;

/// The core layout cannot change while the machine is up.
pub fn read() -> Result<CoreCount, VitalsError> {
    static CACHE: crate::cache::Ttl<CoreCount> = crate::cache::Ttl::sticky();
    CACHE.get_or_try(std::time::Duration::from_secs(86_400), read_uncached)
}

fn read_uncached() -> Result<CoreCount, VitalsError> {
    let performance = parse_count(&super::shell::run(
        "sysctl",
        &["-n", "hw.perflevel0.logicalcpu"],
    )?)?;
    let efficiency = parse_count(&super::shell::run(
        "sysctl",
        &["-n", "hw.perflevel1.logicalcpu"],
    )?)?;

    Ok(CoreCount {
        performance,
        efficiency,
        total: performance + efficiency,
    })
}

fn parse_count(raw: &str) -> Result<u32, VitalsError> {
    raw.trim().parse::<u32>().map_err(|_| {
        VitalsError::parse(
            "sysctl -n hw.perflevel{0,1}.logicalcpu",
            format!("`{}` is not a core count", raw.trim()),
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_real_sysctl_output() {
        assert_eq!(parse_count("10\n").unwrap(), 10);
        assert_eq!(parse_count("4\n").unwrap(), 4);
    }

    #[test]
    fn rejects_non_numeric_output() {
        let err = parse_count("oops\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }
}
