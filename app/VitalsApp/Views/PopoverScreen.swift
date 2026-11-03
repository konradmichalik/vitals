enum MetricKind: CaseIterable { case cpu, memory, load, swap }

enum ToolTab: CaseIterable { case ddev, docker, claude, backup }

enum PopoverScreen: Equatable {
    case overview
    case detail(MetricKind)
    case toolchain(ToolTab)
    case activity
    case settings

    var title: String {
        switch self {
        case .overview: return "Vitals"
        case .detail: return "Details"
        case .toolchain: return "Toolchain"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    /// The header icons act as toggles, so pressing one on its own screen leaves it.
    func toggled(_ target: PopoverScreen) -> PopoverScreen {
        if self == target, target == .activity || target == .settings {
            return .overview
        }
        return target
    }
}
