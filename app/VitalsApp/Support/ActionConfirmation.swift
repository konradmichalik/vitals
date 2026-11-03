import Foundation

struct ActionConfirmation: Equatable {
    let title: String
    let body: String
    let command: String
    let effect: String?
    let reversal: String
    let isDestructive: Bool
    /// The verb for both the button that offers the action and the alert's confirm button.
    let buttonLabel: String

    private struct Copy {
        let title: String
        let reversal: String
        let isDestructive: Bool
        let buttonLabel: String
    }

    static func make(for action: SuggestedAction, culpritLabel: String?) -> ActionConfirmation {
        let target = action.target ?? ""
        let copy = copy(for: action.action, target: target, culpritLabel: culpritLabel)
        let command = "vitals --fix \(action.action)" + (action.target.map { " --target \($0)" } ?? "")
        return ActionConfirmation(
            title: copy.title,
            body: "This runs \(command).",
            command: command,
            effect: action.estimate,
            reversal: copy.reversal,
            isDestructive: copy.isDestructive,
            buttonLabel: copy.buttonLabel
        )
    }

    static func buttonLabel(for action: String) -> String {
        copy(for: action, target: "", culpritLabel: nil).buttonLabel
    }

    private static let fixedCopy: [String: Copy] = [
        "kill_runaway_processes": Copy(
            title: "Quit runaway processes?", reversal: "Not reversible", isDestructive: true, buttonLabel: "Quit processes"
        ),
        "poweroff": Copy(
            title: "Power off all DDEV projects?", reversal: "Start projects again one by one", isDestructive: true, buttonLabel: "Power off DDEV"
        ),
        "prune_docker_images": Copy(
            title: "Remove dangling images?", reversal: "Rebuild from Dockerfile if needed", isDestructive: true, buttonLabel: "Prune images"
        ),
        "add_exclusions": Copy(
            title: "Exclude container data from backups?", reversal: "tmutil removeexclusion in Terminal",
            isDestructive: false, buttonLabel: "Exclude"
        ),
        "stop_backup": Copy(title: "Stop the running backup?", reversal: "Resumes on its own", isDestructive: false, buttonLabel: "Stop backup"),
        "kill_orphaned_agents": Copy(
            title: "Quit orphaned agents?", reversal: "PhpStorm starts new ones", isDestructive: false, buttonLabel: "Quit agents"
        ),
    ]

    private static func copy(for action: String, target: String, culpritLabel: String?) -> Copy {
        switch action {
        case "stop_project":
            return Copy(title: "Stop ddev project \(target)?", reversal: "Start again with ddev start \(target)",
                        isDestructive: false, buttonLabel: "Stop")
        case "start_project":
            return Copy(title: "Start ddev project \(target)?", reversal: "Stop it again", isDestructive: false, buttonLabel: "Start")
        case "kill_process":
            return Copy(title: "Quit \(culpritLabel ?? "this process")?", reversal: "Not reversible",
                        isDestructive: true, buttonLabel: "Quit")
        default:
            return fixedCopy[action] ?? Copy(
                title: "Run “\(action)”?", reversal: "Check the action's output", isDestructive: false,
                buttonLabel: sentenceCased(action)
            )
        }
    }

    private static func sentenceCased(_ name: String) -> String {
        let words = name.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
