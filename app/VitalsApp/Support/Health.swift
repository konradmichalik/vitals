import Foundation

/// The one-sentence verdict at the top of the popover. Memory pressure as
/// reported by macOS comes first because it is what precedes crashes and
/// freezes; CPU only speaks when memory is fine. Nothing here predicts —
/// every sentence states a measured value.
struct HealthSummary: Equatable {
    enum Tone: Equatable {
        case calm
        case warning
        case critical
    }

    enum Focus: Equatable {
        case none
        case memory
        case cpu
    }

    let tone: Tone
    let focus: Focus
    let title: String
    let detail: String

    /// Sustained CPU above this counts as saturated for the summary.
    static let cpuSaturatedPercent: Double = 90

    static func from(report: VitalsReport, cpuSaturated: Bool) -> HealthSummary {
        let memory = report.system.memory
        let free = memory.availableBytes.map(Format.gigabytes) ?? "\(memory.freePercent)%"
        let swap = Format.gigabytes(memory.swapUsedBytes)
        switch memory.pressureLevel {
        case .critical:
            return HealthSummary(
                tone: .critical, focus: .memory, title: "Memory pressure is critical",
                detail: "\(free) free, \(swap) in swap. macOS may now end apps to recover memory."
            )
        case .warn:
            return HealthSummary(
                tone: .warning, focus: .memory, title: "Memory is getting tight",
                detail: "macOS reports memory pressure. \(free) free, \(swap) in swap."
            )
        case .normal:
            break
        }
        if cpuSaturated || report.findings.contains(where: { $0.rule == "runaway_processes" }) {
            let top = report.processes.topByCpu.first.map { " Busiest: \($0.name)." } ?? ""
            let used = Int((100 - report.system.cpu.idlePercent).rounded())
            return HealthSummary(
                tone: .critical, focus: .cpu, title: "CPU is saturated",
                detail: "\(used)% in use.\(top)"
            )
        }
        return HealthSummary(
            tone: .calm, focus: .none, title: "All calm",
            detail: "\(free) free. Nothing is slowing your Mac down."
        )
    }
}

/// Menu bar state: how full memory is, and the value worth showing next
/// to the gauge when something needs attention.
struct MenuBarState: Equatable {
    enum Tone: Equatable {
        case normal
        case warning
        case critical
    }

    let fill: Double
    let tone: Tone
    let label: String?

    static func from(report: VitalsReport?, summary: HealthSummary?) -> MenuBarState {
        guard let report else { return MenuBarState(fill: 0, tone: .normal, label: nil) }
        let memory = report.system.memory
        let fill = min(max(Double(memory.usedPercent) / 100, 0), 1)
        let free = memory.availableBytes.map(Format.gigabytes)
        switch (summary?.tone, summary?.focus) {
        case (.critical?, .cpu?):
            let used = Int((100 - report.system.cpu.idlePercent).rounded())
            return MenuBarState(fill: fill, tone: .critical, label: "CPU \(used)%")
        case (.critical?, _):
            return MenuBarState(fill: fill, tone: .critical, label: free)
        case (.warning?, _):
            return MenuBarState(fill: fill, tone: .warning, label: free)
        default:
            return MenuBarState(fill: fill, tone: .normal, label: nil)
        }
    }
}
