import Foundation

/// One thing the user (or Guard) asked to run, with everything the UI
/// needs around it: a busy key, the confirmation text when the action
/// interrupts work, the toast text, and how to undo it.
struct ActionRequest: Identifiable, Equatable, Sendable {
    struct Confirmation: Equatable, Sendable {
        let title: String
        let body: String
        let effect: String
        let verb: String
        let destructive: Bool
    }

    struct Undo: Equatable, Sendable {
        let action: String
        let label: String
    }

    let id: String
    let action: String
    let targets: [String]
    var scope: [String]?
    let logTitle: String
    let doneText: String
    var confirmation: Confirmation?
    var undo: Undo?

    var commandPreview: String {
        var parts = ["vitals --fix \(action)"]
        if !targets.isEmpty { parts.append("--target \(targets.joined(separator: ","))") }
        if let scope, !scope.isEmpty { parts.append("--scope \(scope.joined(separator: ","))") }
        return parts.joined(separator: " ")
    }

    static func quickWin(_ win: QuickWin) -> ActionRequest {
        let gain = win.reclaimableBytes > 0 ? " · about \(Format.gigabytes(win.reclaimableBytes))" : ""
        var request = ActionRequest(
            id: "win:\(win.id)", action: win.action, targets: win.targets,
            logTitle: win.title, doneText: "\(win.title) done\(gain)"
        )
        if win.confirm {
            request.confirmation = Confirmation(
                title: "\(win.title)?", body: win.detail, effect: gain.isEmpty ? "CPU" : String(gain.dropFirst(3)),
                verb: win.label, destructive: true
            )
        }
        if let undo = win.undoAction {
            request.undo = Undo(action: undo, label: "Start again")
        }
        return request
    }

    static func item(_ item: ConsumerItem, action: ItemAction) -> ActionRequest {
        let targets = action.target.map { [$0] } ?? []
        var request = ActionRequest(
            id: "item:\(item.id)", action: action.action, targets: targets,
            logTitle: "\(action.label) \(item.name)",
            doneText: "\(item.name): \(action.label.lowercased()) done · about \(Format.gigabytes(item.memBytes))"
        )
        if action.confirm {
            request.confirmation = confirmation(for: item, action: action)
        }
        if action.action == "stop_project" {
            request.undo = Undo(action: "start_project", label: "Start again")
        }
        return request
    }

    static func freeIdle(bytes: UInt64, scope: [String]?, byGuard: Bool = false) -> ActionRequest {
        ActionRequest(
            id: byGuard ? "guard" : "relief", action: "free_idle", targets: [], scope: scope,
            logTitle: byGuard ? "Guard freed idle items" : "Freed idle items",
            doneText: "About \(Format.gigabytes(bytes)) freed"
        )
    }

    private static func confirmation(for item: ConsumerItem, action: ItemAction) -> Confirmation {
        let body: String
        switch action.action {
        case "restart_app":
            body = "Quits and reopens \(item.name). It asks about unsaved work itself."
        case "quit_app":
            body = "Asks \(item.name) to quit. Whether windows and tabs come back depends on the app's own settings."
        case "kill_session":
            body = "Ends \(item.name) while it is still active. A Claude Code session can be resumed with claude --continue."
        default:
            body = "Interrupts \(item.name)."
        }
        return Confirmation(
            title: "\(action.label) \(item.name)?", body: body,
            effect: "about \(Format.gigabytes(item.memBytes))", verb: action.label, destructive: true
        )
    }
}

/// A short message at the bottom of the popover after an action.
struct Toast: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let success: Bool
    var undo: ActionRequest?
}
