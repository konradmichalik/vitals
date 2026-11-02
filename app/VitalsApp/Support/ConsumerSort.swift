import Foundation

enum ConsumerSort: CaseIterable {
    case cpu, memory

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        }
    }

    /// Ties keep report order so rows do not reshuffle between refreshes.
    static func sorted(_ consumers: [Consumer], by sort: ConsumerSort) -> [Consumer] {
        consumers.enumerated()
            .sorted { lhs, rhs in
                switch sort {
                case .cpu where lhs.element.cpuPercent != rhs.element.cpuPercent:
                    return lhs.element.cpuPercent > rhs.element.cpuPercent
                case .memory where lhs.element.memBytes != rhs.element.memBytes:
                    return lhs.element.memBytes > rhs.element.memBytes
                default:
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    static func defaultSort(for findings: [Finding]) -> ConsumerSort {
        findings.verdictFinding?.rule == "memory_pressure" ? .memory : .cpu
    }
}
