import Foundation

/// Nothing in the app previously hinted that `~/.vitals.toml` existed at
/// all, so every threshold and the rule ignore list were effectively
/// invisible to anyone who hadn't read the source. Rather than mirroring
/// each value as a native control — which would mean writing TOML back
/// out from Swift and clobbering hand-written comments — Settings writes
/// this fully commented template once and opens it.
///
/// Rule names are deliberately not enumerated here: they live in
/// `core/src/rules.rs`, and a hardcoded copy would drift silently. The
/// report itself is the authoritative list, so the comment points there.
enum ConfigTemplate {
    static let path = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".vitals.toml")

    static let contents = """
        # Vitals configuration — every setting below is optional and shown
        # with its default. Uncomment a line to override it.

        [rules]
        # Rule names to suppress entirely. Use the name shown for a finding
        # in `vitals --json` (its "rule" field), e.g. "unmanaged_docker_containers".
        # ignore = []

        [thresholds]
        # Load average, as a multiple of the performance-core count.
        # load_warn_factor = 1.0
        # load_critical_factor = 1.5

        # Memory ballast: compressed memory plus uptime before suggesting a restart.
        # compressor_warn_gb = 8.0
        # uptime_warn_days = 7.0

        # Claude Code sessions older than this count as stale.
        # stale_session_days = 3.0

        # Time Machine changed-item count that counts as a large scan.
        # changed_items_warn = 20000

        # Reclaimable space before dangling Docker images are worth pruning.
        # docker_reclaimable_warn_gb = 5.0

        # A process must exceed this CPU *and* age to count as a runaway.
        # 700% means seven full cores sustained; `ps` reports a lifetime
        # average, so brief bursts cannot reach it.
        # runaway_cpu_percent = 700.0
        # runaway_min_minutes = 20.0

        # OrbStack CPU above which containers are blamed for high load.
        # orbstack_cpu_percent = 200.0

        # CPU above which a mutagen process counts as actively syncing.
        # mutagen_cpu_percent = 20.0

        # How many IDE ACP agents may run before the count alone reads as a leak.
        # acp_agent_warn_count = 3

        [watch]
        # Paths that should be excluded from Time Machine backups.
        # timemachine_exclusions = ["~/.orbstack", "~/.ddev"]

        [ide]
        # IDE versions that should no longer have agents running.
        # retired_versions = []

        [actions]
        # The menu bar app always confirms before running an action; this
        # only affects `vitals --fix` on the command line.
        # require_confirmation = true

        """

    /// Returns the file's URL, writing the template first if nothing is
    /// there yet. An existing config is never touched.
    static func ensureExists() throws -> URL {
        guard !FileManager.default.fileExists(atPath: path.path) else { return path }
        try contents.write(to: path, atomically: true, encoding: .utf8)
        return path
    }
}
