//! `sysctl -n vm.swapusage` → total/used/free swap.
//!
//! Swap accumulates over uptime and is not a live signal — 20 GB of swap
//! can be two weeks of accumulation with a healthy pageout/pagein ratio.
//! Callers should compare the *delta* in pageouts between samples, not
//! this absolute figure, when judging real memory scarcity (§7).

use crate::error::VitalsError;

#[derive(Debug, Clone, Copy, Default)]
pub struct SwapUsage {
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub free_bytes: u64,
}

pub fn read() -> Result<SwapUsage, VitalsError> {
    let raw = super::shell::run("sysctl", &["-n", "vm.swapusage"])?;
    parse(&raw)
}

fn parse(raw: &str) -> Result<SwapUsage, VitalsError> {
    let parse_error = |reason: String| VitalsError::parse("sysctl -n vm.swapusage", reason);

    let mut fields = raw.split_whitespace();
    let total_bytes = parse_field(&mut fields, "total", &parse_error)?;
    let used_bytes = parse_field(&mut fields, "used", &parse_error)?;
    let free_bytes = parse_field(&mut fields, "free", &parse_error)?;

    Ok(SwapUsage {
        total_bytes,
        used_bytes,
        free_bytes,
    })
}

fn parse_field(
    fields: &mut std::str::SplitWhitespace<'_>,
    name: &str,
    parse_error: &impl Fn(String) -> VitalsError,
) -> Result<u64, VitalsError> {
    let key = fields
        .next()
        .ok_or_else(|| parse_error(format!("expected `{name}` field")))?;
    if key != name {
        return Err(parse_error(format!(
            "expected `{name}` field, found `{key}`"
        )));
    }

    let equals = fields
        .next()
        .ok_or_else(|| parse_error(format!("expected `=` after `{name}`")))?;
    if equals != "=" {
        return Err(parse_error(format!("expected `=` after `{name}`")));
    }

    let value = fields
        .next()
        .ok_or_else(|| parse_error(format!("expected a value for `{name}`")))?;
    parse_size(value).ok_or_else(|| parse_error(format!("`{value}` is not a valid size")))
}

fn parse_size(value: &str) -> Option<u64> {
    let (number, multiplier) = match value.chars().last()? {
        'k' | 'K' => (&value[..value.len() - 1], 1024.0),
        'm' | 'M' => (&value[..value.len() - 1], 1024.0 * 1024.0),
        'g' | 'G' => (&value[..value.len() - 1], 1024.0 * 1024.0 * 1024.0),
        _ => return None,
    };

    let magnitude = number.parse::<f64>().ok()?;
    Some((magnitude * multiplier).round() as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_real_sysctl_output() {
        let swap =
            parse("total = 15360.00M  used = 14184.50M  free = 1175.50M  (encrypted)").unwrap();
        assert_eq!(swap.total_bytes, (15360.00 * 1024.0 * 1024.0) as u64);
        assert_eq!(swap.used_bytes, (14184.50 * 1024.0 * 1024.0) as u64);
        assert_eq!(swap.free_bytes, (1175.50 * 1024.0 * 1024.0) as u64);
    }

    #[test]
    fn parses_output_without_encrypted_marker() {
        let swap = parse("total = 1024.00M  used = 512.00M  free = 512.00M").unwrap();
        assert_eq!(swap.total_bytes, (1024.00 * 1024.0 * 1024.0) as u64);
        assert_eq!(swap.used_bytes, (512.00 * 1024.0 * 1024.0) as u64);
        assert_eq!(swap.free_bytes, (512.00 * 1024.0 * 1024.0) as u64);
    }

    #[test]
    fn rejects_malformed_input() {
        let err = parse("garbage").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn rejects_missing_field() {
        let err = parse("total = 1024.00M  used = 512.00M").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }
}
