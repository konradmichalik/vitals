import Foundation

/// Mirrors the §6 JSON contract emitted by `vitals-core` (see
/// core/src/types.rs). Property names match the JSON's camelCase keys
/// exactly, so no `CodingKeys` are needed.
struct VitalsReport: Codable {
    let schemaVersion: UInt32
    let timestamp: String
    let system: SystemInfo
    let timeMachine: TimeMachineInfo
    let ddev: DdevInfo
    let docker: DockerInfo
    let processes: ProcessesInfo
    let findings: [Finding]
}

struct SystemInfo: Codable {
    let uptimeSeconds: UInt64
    let load: LoadAverage
    let cores: CoreCount
    let memory: MemoryInfo
    let cpu: CpuUsage
}

struct CpuUsage: Codable {
    let userPercent: Double
    let systemPercent: Double
    let idlePercent: Double
}

struct LoadAverage: Codable {
    let m1: Double
    let m5: Double
    let m15: Double
}

struct CoreCount: Codable {
    let performance: UInt32
    let efficiency: UInt32
    let total: UInt32
}

enum PressureLevel: String, Codable, Equatable {
    case normal
    case warn
    case critical
}

struct MemoryInfo: Codable {
    let pressureLevel: PressureLevel
    let freePercent: UInt8
    let usedPercent: UInt8
    let pageSizeBytes: UInt64
    let compressorBytes: UInt64
    let swapUsedBytes: UInt64
    let pageouts: UInt64
}

struct TimeMachineInfo: Codable {
    let running: Bool
    let phase: String?
    let changedItemCount: UInt64?
    let exclusions: [TmExclusion]
}

struct TmExclusion: Codable {
    let path: String
    let excluded: Bool
}

struct DdevInfo: Codable {
    let running: [String]
    let problems: [String]
    let pausedCount: UInt32
    let stoppedCount: UInt32
}

struct DockerInfo: Codable {
    let containers: [DockerContainer]
}

struct DockerContainer: Codable, Identifiable {
    let id: String
    let name: String
    let image: String
    let cpuPercent: Double
    let memBytes: UInt64
    let ddevManaged: Bool
    let ddevProject: String?
    let composeProject: String?
}

struct ProcessesInfo: Codable {
    let claudeSessions: [ClaudeSession]
    let acpAgents: [AcpAgent]
    let orbstack: OrbstackProcess?
}

struct ClaudeSession: Codable {
    let pid: UInt32
    let etimeSeconds: UInt64
    let cpuPercent: Double
    let rssBytes: UInt64
    let kind: String
    let version: String
}

struct AcpAgent: Codable {
    let pid: UInt32
    let etimeSeconds: UInt64
    let ideVersion: String
    let orphaned: Bool
}

struct OrbstackProcess: Codable {
    let pid: UInt32
    let cpuPercent: Double
    let rssBytes: UInt64
}

/// Order matches `core/src/types.rs`'s derive(Ord) — declaration order
/// info < warn < critical — so `max()` picks the right traffic-light color.
enum Severity: String, Codable, Comparable {
    case info
    case warn
    case critical

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warn: return 1
        case .critical: return 2
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}

struct Finding: Codable, Identifiable {
    let rule: String
    let severity: Severity
    let message: String
    let actions: [String]

    var id: String { rule }
}

/// The `{"schemaVersion":...,"error":...}` shape `vitals_collect` returns
/// on failure (see app/vitals-ffi/src/lib.rs's `error_json`).
struct VitalsAPIError: Codable {
    let schemaVersion: UInt32
    let error: String
}
