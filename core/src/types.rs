//! JSON contract types (`vitals --json`). See concept doc §6 — this is the
//! interface the menubar app and other consumers rely on, so any breaking
//! change to a field must bump [`SCHEMA_VERSION`].

use serde::{Deserialize, Serialize};

pub const SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VitalsReport {
    pub schema_version: u32,
    pub timestamp: String,
    pub system: SystemInfo,
    pub time_machine: TimeMachineInfo,
    pub ddev: DdevInfo,
    pub processes: ProcessesInfo,
    pub findings: Vec<Finding>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemInfo {
    pub uptime_seconds: u64,
    pub load: LoadAverage,
    pub cores: CoreCount,
    pub memory: MemoryInfo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadAverage {
    pub m1: f64,
    pub m5: f64,
    pub m15: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoreCount {
    pub performance: u32,
    pub efficiency: u32,
    pub total: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PressureLevel {
    Normal,
    Warn,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MemoryInfo {
    pub pressure_level: PressureLevel,
    pub free_percent: u8,
    pub page_size_bytes: u64,
    pub compressor_bytes: u64,
    pub swap_used_bytes: u64,
    pub pageouts: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimeMachineInfo {
    pub running: bool,
    pub phase: Option<String>,
    pub changed_item_count: Option<u64>,
    pub exclusions: Vec<TmExclusion>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TmExclusion {
    pub path: String,
    pub excluded: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DdevInfo {
    pub running: Vec<String>,
    pub problems: Vec<String>,
    pub paused_count: u32,
    pub stopped_count: u32,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessesInfo {
    pub claude_sessions: Vec<ClaudeSession>,
    pub acp_agents: Vec<AcpAgent>,
    pub orbstack: Option<OrbstackProcess>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaudeSession {
    pub pid: u32,
    pub etime_seconds: u64,
    pub cpu_percent: f64,
    pub rss_bytes: u64,
    pub kind: String,
    pub version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AcpAgent {
    pub pid: u32,
    pub etime_seconds: u64,
    pub ide_version: String,
    pub orphaned: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OrbstackProcess {
    pub pid: u32,
    pub cpu_percent: f64,
    pub rss_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Info,
    Warn,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Finding {
    pub rule: String,
    pub severity: Severity,
    pub message: String,
    pub actions: Vec<String>,
}
