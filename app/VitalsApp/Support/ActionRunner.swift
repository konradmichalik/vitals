import Foundation

/// Actions stay CLI-side (§9, §11.2 open decision — resolved here in
/// favor of the app invoking the CLI): the app shows its own native
/// confirmation dialog, then runs `vitals --fix <action> --yes` via
/// `Process` so the CLI's interactive y/N prompt is bypassed. `core`
/// never prompts or reads stdin; only `cli` does, and only when `--yes`
/// is absent.
enum ActionRunnerError: Error, Equatable {
    case vitalsNotFound
    case launchFailed(String)
    case nonZeroExit(String)

    /// Notifications previously interpolated the case itself, so the user
    /// read "Failed: vitalsNotFound" — a symbol name, not an explanation
    /// of what went wrong or what to do about it.
    var message: String {
        switch self {
        case .vitalsNotFound:
            return "Couldn't find the vitals command line tool "
                + "(looked in /opt/homebrew/bin, /usr/local/bin and your PATH)."
        case .launchFailed(let reason):
            return "Couldn't start the vitals command line tool: \(reason)"
        case .nonZeroExit(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "The action failed without reporting a reason." : trimmed
        }
    }
}

enum ActionRunner {
    /// Homebrew's two install locations stay ahead of PATH: PATH is
    /// searched as a fallback for non-standard installs, but letting it
    /// win would let an unrelated `vitals` earlier in PATH shadow the
    /// real one.
    private static let knownInstallPaths = [
        "/opt/homebrew/bin/vitals",
        "/usr/local/bin/vitals",
    ]

    static func candidatePaths(
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> [String] {
        let fromPath = (pathEnvironment ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { "\($0)/vitals" }

        var seen: Set<String> = []
        return (knownInstallPaths + fromPath).filter { seen.insert($0).inserted }
    }

    /// A finding's `actions` can include entries that aren't invokable
    /// CLI actions at all (`list_running_projects`, `list_with_age` —
    /// informational-only per §9's design), or that need a target this
    /// app has no safe way to determine from a `Finding` alone
    /// (`stop_project`, `kill_session`). Only the target-less real CLI
    /// actions get a "Run" button; everything else is shown as plain text.
    static let runnableActions: Set<String> = [
        "poweroff", "stop_backup", "add_exclusions", "kill_orphaned_agents",
        "prune_docker_images", "kill_runaway_processes",
    ]

    static func buildArguments(action: String, target: String?) -> [String] {
        var args = ["--fix", action, "--yes"]
        if let target {
            args += ["--target", target]
        }
        return args
    }

    static func locateVitalsBinary(
        candidates: [String] = candidatePaths(),
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        candidates.first(where: fileExists)
    }

    @discardableResult
    static func run(action: String, target: String?) -> Result<String, ActionRunnerError> {
        guard let vitalsPath = locateVitalsBinary() else {
            return .failure(.vitalsNotFound)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: vitalsPath)
        process.arguments = buildArguments(action: action, target: target)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return .success(output)
        }
        return .failure(.nonZeroExit(output))
    }
}
