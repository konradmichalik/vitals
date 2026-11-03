import SwiftUI

typealias ActionRequest = (SuggestedAction, String?) -> Void

/// One list row: a combined label on the left, an optional action button on the right.
struct ToolchainRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    var button: ToolchainButton?

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(title).font(.callout).lineLimit(1).truncationMode(.middle)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            button
        }
        .padding(.vertical, 4)
    }
}

/// Uses the confirmation copy's verb and names its target for VoiceOver.
struct ToolchainButton: View {
    let action: SuggestedAction
    var targetName: String?
    var culpritLabel: String?
    let isRunning: Bool
    let onAction: ActionRequest

    var body: some View {
        let verb = ActionConfirmation.buttonLabel(for: action.action)
        Button(verb) { onAction(action, culpritLabel) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRunning)
            .accessibilityLabel([verb, targetName].compactMap { $0 }.joined(separator: " "))
    }
}

struct ToolchainEmptyText: View {
    let text: String

    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }
}

struct ToolchainSummaryText: View {
    let text: String

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
