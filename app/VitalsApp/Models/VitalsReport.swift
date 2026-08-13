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
    let topByCpu: [TopProcess]
}

struct TopProcess: Codable, Identifiable {
    let pid: UInt32
    let name: String
    let cpuPercent: Double

    var id: UInt32 { pid }
}

struct ClaudeSession: Codable, Identifiable {
    let pid: UInt32
    let etimeSeconds: UInt64
    let cpuPercent: Double
    let rssBytes: UInt64
    let kind: String
    let version: String
    let workingDirectory: String?

    var id: UInt32 { pid }

    /// Every session on a machine typically shares the same `version`,
    /// so it doesn't tell parallel sessions apart the way their project
    /// does — this falls back to the version only when no working
    /// directory could be resolved at all.
    var projectLabel: String {
        guard let workingDirectory, let name = workingDirectory.split(separator: "/").last else {
            return "v\(version)"
        }
        return String(name)
    }
}

struct ClaudeSessionGroup: Identifiable {
    let label: String
    let count: Int
    let longestEtimeSeconds: UInt64
    let cpuPercent: Double

    var id: String { label }
}

extension [ClaudeSession] {
    /// Parallel sessions in the same project are common (multiple
    /// terminal tabs on the same repo) and would otherwise repeat the
    /// same project label as several indistinguishable rows.
    func groupedByProject() -> [ClaudeSessionGroup] {
        Dictionary(grouping: self, by: \.projectLabel)
            .map { label, sessions in
                ClaudeSessionGroup(
                    label: label,
                    count: sessions.count,
                    longestEtimeSeconds: sessions.map(\.etimeSeconds).max() ?? 0,
                    cpuPercent: sessions.reduce(0) { $0 + $1.cpuPercent }
                )
            }
            .sorted { $0.cpuPercent != $1.cpuPercent ? $0.cpuPercent > $1.cpuPercent : $0.label < $1.label }
    }
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

extension [Finding] {
    /// `rules::evaluate` (core/src/rules.rs) emits findings in a fixed
    /// rule order, not by severity — without this, a critical finding can
    /// end up listed below several infos. `enumerated()` breaks ties by
    /// original position so same-severity findings don't reshuffle
    /// between refreshes. `Array.sorted` isn't guaranteed stable on its
    /// own.
    func sortedBySeverity() -> [Finding] {
        enumerated()
            .sorted { lhs, rhs in
                lhs.element.severity != rhs.element.severity
                    ? lhs.element.severity > rhs.element.severity
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// The `{"schemaVersion":...,"error":...}` shape `vitals_collect` returns
/// on failure (see app/vitals-ffi/src/lib.rs's `error_json`).
struct VitalsAPIError: Codable {
    let schemaVersion: UInt32
    let error: String
}
