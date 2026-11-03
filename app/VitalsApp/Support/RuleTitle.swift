import Foundation

/// Short names for the rule ids in core/src/rules.rs. Settings lists snoozes by rule
/// after the finding itself may be gone, so the finding's message is not available.
enum RuleTitle {
    private static let titles: [String: String] = [
        "load_status": "High load",
        "memory_pressure": "Memory pressure",
        "runaway_processes": "Runaway processes",
        "backup_scanning_container_data": "Backup scanning containers",
        "backup_paths_not_excluded": "Container data in backups",
        "container_load": "Container load",
        "mutagen_active": "Mutagen sync active",
        "reclaimable_docker_images": "Unused Docker images",
        "unmanaged_docker_containers": "Containers outside DDEV",
        "uptime_ballast": "Memory ballast",
        "orphaned_acp_agents": "PhpStorm agents",
        "stale_claude_sessions": "Old Claude sessions",
        "ddev_project_problems": "DDEV project problems",
    ]

    /// Unknown ids fall back to the id, so a rule added in core still shows up.
    static func title(for rule: String) -> String {
        titles[rule] ?? rule
    }
}
