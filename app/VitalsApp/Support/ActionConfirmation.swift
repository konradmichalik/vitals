import Foundation

struct ActionConfirmation: Equatable {
    let title: String
    let body: String
    let command: String
    let effect: String?
    let reversal: String
    let isDestructive: Bool

    static func make(for action: SuggestedAction, culpritLabel: String?) -> ActionConfirmation {
        let target = action.target ?? ""
        let copy = copy(for: action.action, target: target, culpritLabel: culpritLabel)
        let command = "vitals --fix \(action.action)" + (action.target.map { " --target \($0)" } ?? "")
        return ActionConfirmation(
            title: copy.title,
            body: "This runs `\(command)`.",
            command: command,
            effect: action.estimate,
            reversal: copy.reversal,
            isDestructive: copy.isDestructive
        )
    }

    private static func copy(
        for action: String,
        target: String,
        culpritLabel: String?
    ) -> (title: String, reversal: String, isDestructive: Bool) {
        switch action {
        case "stop_project":
            return ("Stop ddev project \(target)?", "Start again with ddev start \(target)", false)
        case "start_project":
            return ("Start ddev project \(target)?", "Stop it again", false)
        case "kill_process":
            return ("Quit \(culpritLabel ?? "this process")?", "Not reversible", true)
        case "poweroff":
            return ("Power off all DDEV projects?", "Start projects again one by one", true)
        case "prune_docker_images":
            return ("Remove dangling images?", "Rebuild from Dockerfile if needed", true)
        case "add_exclusions":
            return ("Exclude container data from backups?", "tmutil removeexclusion in Terminal", false)
        case "stop_backup":
            return ("Stop the running backup?", "Resumes on its own", false)
        case "kill_orphaned_agents":
            return ("Quit orphaned agents?", "PhpStorm starts new ones", false)
        default:
            return ("Run “\(action)”?", "Check the action's output", false)
        }
    }
}
