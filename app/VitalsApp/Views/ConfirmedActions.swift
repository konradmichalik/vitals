import SwiftUI

struct PendingAction {
    let action: SuggestedAction
    let confirmation: ActionConfirmation

    init(_ action: SuggestedAction, culpritLabel: String?) {
        self.action = action
        confirmation = ActionConfirmation.make(for: action, culpritLabel: culpritLabel)
    }
}

private struct ConfirmedActions: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Binding var pending: PendingAction?

    func body(content: Content) -> some View {
        content.alert(
            pending?.confirmation.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { pending in
            Button(pending.confirmation.buttonLabel, role: pending.confirmation.isDestructive ? .destructive : nil) {
                appState.perform(pending.action)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(Self.message(for: pending.confirmation))
        }
    }

    private static func message(for confirmation: ActionConfirmation) -> String {
        let effect = confirmation.effect.map { "Effect: \($0)" }
        return [confirmation.body, effect, confirmation.reversal].compactMap { $0 }.joined(separator: "\n")
    }
}

extension View {
    /// Every screen that offers an action shares this one confirmation before `appState.perform` runs.
    func confirmingActions(_ pending: Binding<PendingAction?>) -> some View {
        modifier(ConfirmedActions(pending: pending))
    }
}
