//! `sysctl -n vm.loadavg` → 1/5/15 min load averages.

use crate::error::VitalsError;
use crate::types::LoadAverage;

pub fn read() -> Result<LoadAverage, VitalsError> {
    let raw = super::shell::run("sysctl", &["-n", "vm.loadavg"])?;
    parse(&raw)
}

fn parse(raw: &str) -> Result<LoadAverage, VitalsError> {
    const COMMAND: &str = "sysctl -n vm.loadavg";

    let values: Vec<f64> = raw
        .trim()
        .trim_start_matches('{')
        .trim_end_matches('}')
        .split_whitespace()
        .map(|token| {
            token
                .parse::<f64>()
                .map_err(|_| VitalsError::parse(COMMAND, format!("`{token}` is not a number")))
        })
        .collect::<Result<_, _>>()?;

    match values[..] {
        [m1, m5, m15] => Ok(LoadAverage { m1, m5, m15 }),
        _ => Err(VitalsError::parse(
            COMMAND,
            "expected exactly 3 space-separated values",
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_real_sysctl_output() {
        let load = parse("{ 3.27 10.78 9.82 }\n").unwrap();
        assert_eq!(load.m1, 3.27);
        assert_eq!(load.m5, 10.78);
        assert_eq!(load.m15, 9.82);
    }

    #[test]
    fn rejects_wrong_value_count() {
        let err = parse("{ 3.27 10.78 }\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn rejects_non_numeric_values() {
        let err = parse("{ oops 10.78 9.82 }\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }
}
