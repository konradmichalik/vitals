//! vitals-core: probes, parsing and rule engine backing the `vitals` CLI.
//!
//! macOS-only. See the project's concept document (§4–§7) for the data
//! sources this crate reads and the parsing pitfalls each probe must guard
//! against.

pub mod actions;
pub mod classify;
pub mod config;
pub mod error;
pub mod probes;
pub mod report;
pub mod rules;
pub mod types;

pub use error::VitalsError;
