//! One module per data source in the concept doc's §4 probe table. Each
//! probe shells out to a system command and parses its output into the
//! corresponding §6 JSON-contract type.
//!
//! Probes are stubs until v0.1 lands — see §7 for the parsing pitfalls
//! (page size, `ps` comm vs command, `tmutil status -X` as plist, etc.)
//! each implementation must guard against.

pub mod cores;
pub mod cpu;
pub mod ddev;
pub mod docker;
pub mod load;
pub mod memory;
pub mod orbstack;
pub mod processes;
pub mod swap;
pub mod time_machine;
pub mod uptime;
pub mod vm_stat;

pub(crate) mod shell;

/// Shared by every probe that shells out to a `--json`/JSON-Lines command
/// (`ddev list`, `docker ps`, `docker stats`) and needs a specific string
/// field out of a `serde_json::Value` record, erroring with the same
/// shape when it's missing or non-string.
pub(crate) fn json_field(
    value: &serde_json::Value,
    key: &str,
    command: &str,
) -> Result<String, crate::error::VitalsError> {
    value
        .get(key)
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .ok_or_else(|| {
            crate::error::VitalsError::parse(
                command,
                format!("missing or non-string \"{key}\" field"),
            )
        })
}
