//! `vm_stat` → pages free/active/inactive/compressor, pageins/pageouts.
//!
//! Page size must be parsed from the `vm_stat` header line, never
//! hardcoded — it's 16384 bytes on Apple Silicon, not the traditional
//! 4096 (§7).

use crate::error::VitalsError;

#[derive(Debug, Clone, Copy, Default)]
pub struct VmStat {
    pub page_size_bytes: u64,
    pub free_pages: u64,
    pub active_pages: u64,
    pub inactive_pages: u64,
    pub compressor_pages: u64,
    pub pageins: u64,
    pub pageouts: u64,
}

impl VmStat {
    pub fn compressor_bytes(&self) -> u64 {
        self.compressor_pages * self.page_size_bytes
    }
}

pub fn read() -> Result<VmStat, VitalsError> {
    let raw = super::shell::run("vm_stat", &[])?;
    parse(&raw)
}

fn parse(raw: &str) -> Result<VmStat, VitalsError> {
    const COMMAND: &str = "vm_stat";
    let parse_error = |reason: &str| VitalsError::parse(COMMAND, reason);

    let mut lines = raw.lines();
    let header = lines.next().ok_or_else(|| parse_error("empty output"))?;

    let page_size_bytes: u64 = header
        .split("page size of ")
        .nth(1)
        .and_then(|rest| rest.split(" bytes").next())
        .ok_or_else(|| parse_error("missing page size header"))?
        .parse()
        .map_err(|_| parse_error("page size is not a number"))?;

    let mut free_pages = None;
    let mut active_pages = None;
    let mut inactive_pages = None;
    let mut compressor_pages = None;
    let mut pageins = None;
    let mut pageouts = None;

    for line in lines {
        let Some((label, value)) = line.split_once(':') else {
            continue;
        };
        let label = label.trim().trim_matches('"');
        let value: u64 = match value.trim().trim_end_matches('.').parse() {
            Ok(value) => value,
            Err(_) => continue,
        };

        match label {
            "Pages free" => free_pages = Some(value),
            "Pages active" => active_pages = Some(value),
            "Pages inactive" => inactive_pages = Some(value),
            "Pages occupied by compressor" => compressor_pages = Some(value),
            "Pageins" => pageins = Some(value),
            "Pageouts" => pageouts = Some(value),
            _ => {}
        }
    }

    Ok(VmStat {
        page_size_bytes,
        free_pages: free_pages.ok_or_else(|| parse_error("missing `Pages free`"))?,
        active_pages: active_pages.ok_or_else(|| parse_error("missing `Pages active`"))?,
        inactive_pages: inactive_pages.ok_or_else(|| parse_error("missing `Pages inactive`"))?,
        compressor_pages: compressor_pages
            .ok_or_else(|| parse_error("missing `Pages occupied by compressor`"))?,
        pageins: pageins.ok_or_else(|| parse_error("missing `Pageins`"))?,
        pageouts: pageouts.ok_or_else(|| parse_error("missing `Pageouts`"))?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const REAL_OUTPUT: &str = "Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                     4070.
Pages active:                                 288618.
Pages inactive:                               285091.
Pages speculative:                              2276.
Pages throttled:                                   0.
Pages wired down:                             339242.
Pages purgeable:                                  22.
\"Translation faults\":                    33016983560.
Pages copy-on-write:                       870705302.
Pages zero filled:                        5623064777.
Pages reactivated:                       10589579050.
Pages purged:                              978696597.
File-backed pages:                            191150.
Anonymous pages:                              384835.
Pages stored in compressor:                  2805604.
Pages occupied by compressor:                 608855.
Decompressions:                          16923740496.
Compressions:                            17404044312.
Pageins:                                   503523652.
Pageouts:                                    7332338.
Swapins:                                   347889779.
Swapouts:                                  366283234.
";

    #[test]
    fn parses_real_vm_stat_output() {
        let stat = parse(REAL_OUTPUT).unwrap();
        assert_eq!(stat.page_size_bytes, 16384);
        assert_eq!(stat.free_pages, 4070);
        assert_eq!(stat.active_pages, 288618);
        assert_eq!(stat.inactive_pages, 285091);
        assert_eq!(stat.compressor_pages, 608855);
        assert_eq!(stat.pageins, 503523652);
        assert_eq!(stat.pageouts, 7332338);
    }

    #[test]
    fn rejects_empty_input() {
        let err = parse("").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn rejects_missing_page_size_header() {
        let err = parse("Pages free:                                     4070.\n").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn rejects_missing_required_field() {
        let raw = "Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                     4070.
Pages active:                                 288618.
Pages inactive:                               285091.
Pageins:                                   503523652.
Pageouts:                                    7332338.
";
        let err = parse(raw).unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }
}
