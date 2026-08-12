//! One module per data source in the concept doc's §4 probe table. Each
//! probe shells out to a system command and parses its output into the
//! corresponding §6 JSON-contract type.
//!
//! Probes are stubs until v0.1 lands — see §7 for the parsing pitfalls
//! (page size, `ps` comm vs command, `tmutil status -X` as plist, etc.)
//! each implementation must guard against.

pub mod cores;
pub mod ddev;
pub mod load;
pub mod memory;
pub mod orbstack;
pub mod processes;
pub mod swap;
pub mod time_machine;
pub mod uptime;
pub mod vm_stat;

pub(crate) mod shell;
