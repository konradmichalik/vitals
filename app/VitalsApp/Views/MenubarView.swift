import SwiftUI

enum Screen: Equatable {
    case overview
    case group(String)
    case history(Metric)
    case activity
    case incident(String)
    case settings
}

/// The popover: one header, one scrolling screen, and two overlays (the
/// toast after an action and the sheet that asks before interrupting
/// work). Every screen uses the components in `Components.swift`.
struct MenubarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var screen: Screen = .overview

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 360, height: 600)
        .font(.system(size: 13))
        // NSPopover has no opaque backing of its own — without this the
        // system's vibrancy blur shows whatever's on the desktop behind
        // the popover straight through the card tints.
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { toast }
        .overlay { confirmation }
        .animation(.easeOut(duration: 0.25), value: screen)
        .animation(.easeOut(duration: 0.25), value: appState.toast)
        .animation(.easeOut(duration: 0.25), value: appState.pendingConfirmation)
    }

    private var title: String {
        switch screen {
        case .overview: return "Vitals"
        case .group(let id): return appState.report?.consumerGroups.first { $0.id == id }?.name ?? "Details"
        case .history: return "History"
        case .activity: return "Activity"
        case .incident: return "Incident"
        case .settings: return "Settings"
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if screen == .overview {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(appState.summary.map { Theme.color(for: $0.tone) } ?? .secondary)
                    .frame(width: 22, height: 22)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 6))
            } else {
                headerButton("chevron.left", help: "Back") { screen = backTarget }
            }
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            Spacer()
            headerButton("clock", help: "Activity", active: screen == .activity) {
                screen = screen == .activity ? .overview : .activity
            }
            headerButton("gearshape", help: "Settings", active: screen == .settings) {
                screen = screen == .settings ? .overview : .settings
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 44)
    }

    private var backTarget: Screen {
        if case .incident = screen { return .activity }
        return .overview
    }

    private func headerButton(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var content: some View {
        if let report = appState.report {
            screenView(report)
                .transition(.opacity)
        } else if let error = appState.lastError {
            Text(message(for: error)).foregroundStyle(.secondary).padding(.top, 12)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(24)
        }
    }

    @ViewBuilder
    private func screenView(_ report: VitalsReport) -> some View {
        switch screen {
        case .overview:
            OverviewScreen(report: report) { screen = $0 }
        case .group(let id):
            if let group = report.consumerGroups.first(where: { $0.id == id }) {
                GroupScreen(group: group, totalBytes: report.system.memory.totalBytes ?? 0)
            } else {
                Text("This group is no longer running.").foregroundStyle(.secondary)
            }
        case .history(let metric):
            HistoryScreen(metric: metric).id(metric)
        case .activity:
            ActivityScreen(report: report) { screen = .incident($0.id) }
        case .incident(let id):
            if let incident = report.incidentList.first(where: { $0.id == id }) {
                IncidentScreen(incident: incident)
            }
        case .settings:
            SettingsScreen()
        }
    }

    private func message(for error: VitalsCollectError) -> String {
        switch error {
        case .nullPointer, .invalidUTF8, .malformed:
            return "vitals-ffi returned an unexpected response."
        case .reported(let message):
            return message
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let toast = appState.toast {
            ToastView(toast: toast)
                .padding(12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var confirmation: some View {
        if let request = appState.pendingConfirmation, let confirmation = request.confirmation {
            ConfirmSheet(request: request, confirmation: confirmation)
                .transition(.opacity)
        }
    }
}

struct ToastView: View {
    @EnvironmentObject private var appState: AppState
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.success ? "checkmark" : "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(toast.success ? .green : .red)
            Text(toast.text).font(.system(size: 13, weight: .medium)).lineLimit(2)
            Spacer(minLength: 4)
            if let undo = toast.undo {
                RowButton(title: "Start again") {
                    appState.toast = nil
                    appState.perform(undo)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .onHover { inside in
            if inside {
                appState.holdToast()
            } else {
                appState.releaseToast()
            }
        }
    }
}

struct ConfirmSheet: View {
    @EnvironmentObject private var appState: AppState
    let request: ActionRequest
    let confirmation: ActionRequest.Confirmation

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.3)
                .onTapGesture { appState.cancelPending() }
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(confirmation.title).font(.system(size: 17, weight: .semibold))
                    Text(confirmation.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Frees").foregroundStyle(.secondary)
                        Text(confirmation.effect).fontWeight(.semibold)
                    }
                    GridRow {
                        Text("Runs").foregroundStyle(.secondary)
                        Text(request.commandPreview)
                            .font(.system(size: 11.5, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: 12))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                HStack(spacing: 8) {
                    SecondaryButton(title: "Cancel") { appState.cancelPending() }
                        .frame(maxWidth: .infinity)
                    PrimaryButton(title: confirmation.verb, tint: confirmation.destructive ? .red : .accentColor) {
                        appState.confirmPending()
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor), in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
        }
    }
}
