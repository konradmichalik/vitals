//! JSON contract types (`vitals --json`). See concept doc §6 — this is the
//! interface the menubar app and other consumers rely on, so any breaking
//! change to a field must bump [`SCHEMA_VERSION`].

use serde::{Deserialize, Serialize};

pub const SCHEMA_VERSION: u32 = 4;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VitalsReport {
    pub schema_version: u32,
    pub timestamp: String,
    pub system: SystemInfo,
    pub time_machine: TimeMachineInfo,
    pub ddev: DdevInfo,
    pub docker: DockerInfo,
    pub processes: ProcessesInfo,
    pub findings: Vec<Finding>,
    #[serde(default)]
    pub disk: DiskInfo,
    /// Who holds the memory, grouped the way the menubar app shows it.
    #[serde(default)]
    pub consumers: Vec<ConsumerGroup>,
    /// Ready-to-run ways to get memory or CPU back, largest gain first.
    #[serde(default)]
    pub quick_wins: Vec<QuickWin>,
    /// Recent JetsamEvent reports: when macOS itself ended processes
    /// because memory ran out.
    #[serde(default)]
    pub incidents: Vec<Incident>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DiskInfo {
    /// Bytes read and written by all disks since boot (`iostat -I`). A
    /// rate needs two readings; pollers derive it from the difference.
    pub total_bytes: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConsumerGroup {
    /// Stable identifier: `ddev`, `agents`, `phpstorm`, `browser`,
    /// `containers`, `apps` or `system`.
    pub id: String,
    pub name: String,
    pub mem_bytes: u64,
    pub cpu_percent: f64,
    /// The part of `mem_bytes` held by idle items that may be freed.
    pub idle_bytes: u64,
    pub items: Vec<ConsumerItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConsumerItem {
    pub id: String,
    pub name: String,
    pub detail: String,
    pub mem_bytes: u64,
    pub cpu_percent: f64,
    pub idle: bool,
    /// How long this item has shown no activity, when that is known.
    pub idle_seconds: Option<u64>,
    pub protected: bool,
    pub action: Option<ItemAction>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ItemAction {
    /// An `ACTION_NAMES` entry.
    pub action: String,
    pub target: Option<String>,
    pub label: String,
    /// True when running it interrupts work, so a caller must ask first.
    pub confirm: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuickWin {
    pub id: String,
    pub title: String,
    pub detail: String,
    /// Estimated memory returned, from the RSS of the affected processes
    /// or containers. Zero when the gain is not memory (CPU, disk).
    pub reclaimable_bytes: u64,
    pub action: String,
    /// One target per entry; empty for actions that derive their own.
    pub targets: Vec<String>,
    pub label: String,
    pub confirm: bool,
    /// The action that reverses this one, if any (`start_project`).
    pub undo_action: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Incident {
    pub file: String,
    pub date: String,
    pub largest_process: Option<String>,
    pub page_size_bytes: u64,
    /// Processes the report marks with a termination `reason`.
    pub killed: Vec<IncidentProcess>,
    /// The largest processes at the time, by resident pages.
    pub top: Vec<IncidentProcess>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IncidentProcess {
    pub pid: Option<u32>,
    pub name: String,
    pub bytes: u64,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemInfo {
    pub uptime_seconds: u64,
    pub load: LoadAverage,
    pub cores: CoreCount,
    pub memory: MemoryInfo,
    pub cpu: CpuUsage,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoadAverage {
    pub m1: f64,
    pub m5: f64,
    pub m15: f64,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CpuUsage {
    pub user_percent: f64,
    pub system_percent: f64,
    pub idle_percent: f64,
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
    /// active + wired + compressed, as a percent of total — what other
    /// memory tools (Activity Monitor, Stats) mean by "memory used".
    /// `free_percent` alone reads as near-0% on any long-running Mac
    /// (§7: unused RAM works as reclaimable disk cache, it isn't idle),
    /// which looks like a red flag but isn't one — this is the number
    /// worth actually displaying.
    pub used_percent: u8,
    pub page_size_bytes: u64,
    pub compressor_bytes: u64,
    pub swap_used_bytes: u64,
    pub pageouts: u64,
    #[serde(default)]
    pub total_bytes: u64,
    /// `total_bytes` minus active, wired and compressed memory — what is
    /// left before macOS has to compress or swap more.
    #[serde(default)]
    pub available_bytes: u64,
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
    #[serde(default)]
    pub projects: Vec<DdevProjectInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DdevProjectInfo {
    pub name: String,
    pub status: String,
    pub approot: String,
    /// Sum over the project's containers (`docker stats`).
    pub mem_bytes: u64,
    pub cpu_percent: f64,
    /// Seconds since vitals last saw the project's containers busy; only
    /// counts time vitals was running (see `activity`).
    pub idle_seconds: Option<u64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DockerInfo {
    pub containers: Vec<DockerContainer>,
    pub dangling_image_count: u32,
    pub reclaimable_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DockerContainer {
    pub id: String,
    pub name: String,
    pub image: String,
    pub cpu_percent: f64,
    pub mem_bytes: u64,
    /// True for any DDEV-managed container, including its shared,
    /// not-project-specific infrastructure (router, ssh-agent). Separate
    /// from `ddev_project`: DDEV's own shared containers carry the
    /// `com.ddev.platform` label but an empty `com.ddev.site-name`.
    pub ddev_managed: bool,
    pub ddev_project: Option<String>,
    pub compose_project: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessesInfo {
    pub claude_sessions: Vec<ClaudeSession>,
    pub acp_agents: Vec<AcpAgent>,
    pub orbstack: Option<OrbstackProcess>,
    /// The processes actually driving current CPU usage — added so a
    /// critical `load_status` finding isn't just a number with no way to
    /// tell what's causing it.
    pub top_by_cpu: Vec<TopProcess>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TopProcess {
    pub pid: u32,
    pub name: String,
    pub cpu_percent: f64,
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
    /// Distinguishes sessions from each other by project — every session
    /// on a machine typically shares the same `version`, so that alone
    /// doesn't tell parallel sessions apart the way this does.
    pub working_directory: Option<String>,
    /// RSS of the session plus every process it started (MCP servers,
    /// tool runs) — what ending the session gives back.
    #[serde(default)]
    pub tree_rss_bytes: u64,
    /// Seconds since any transcript in the session's working directory
    /// was written. `None` when no transcript was found.
    #[serde(default)]
    pub idle_seconds: Option<u64>,
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
