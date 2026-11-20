import Foundation

extension AppState {
    /// Entry point for every button: asks first when the action
    /// interrupts work, runs it straight away otherwise.
    func request(_ request: ActionRequest) {
        if request.confirmation != nil {
            pendingConfirmation = request
        } else {
            perform(request)
        }
    }

    func confirmPending() {
        guard let request = pendingConfirmation else { return }
        pendingConfirmation = nil
        perform(request)
    }

    func cancelPending() {
        pendingConfirmation = nil
    }

    func freeAllIdle() {
        guard let report, report.idleBytes > 0 else { return }
        perform(.freeIdle(bytes: report.idleBytes, scope: nil))
    }

    /// Frees every idle item of one group with a single CLI call per action.
    func freeIdle(in group: ConsumerGroup) {
        let byAction = Dictionary(grouping: group.idleItems.compactMap { item in
            item.action.map { (item, $0) }
        }, by: { $0.1.action })
        for (action, pairs) in byAction {
            let targets = pairs.compactMap { $0.1.target }
            let bytes = pairs.reduce(UInt64(0)) { $0 + $1.0.memBytes }
            var request = ActionRequest(
                id: "group:\(group.id):\(action)", action: action, targets: targets,
                logTitle: "Freed idle items in \(group.name)",
                doneText: "About \(Format.gigabytes(bytes)) freed"
            )
            if action == "stop_project" {
                request.undo = .init(action: "start_project", label: "Start again")
            }
            perform(request)
        }
    }

    func perform(_ request: ActionRequest) {
        guard !busy.contains(request.id) else { return }
        busy.insert(request.id)
        if request.action == "free_idle" || request.undo != nil {
            measuring = true
        }
        let arguments = ActionRunner.buildArguments(
            action: request.action,
            targets: request.targets,
            scope: request.scope,
            extra: AppSettings.cliArguments(idleMinutes: idleMinutes, protected: protectedItems)
        )
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ActionRunner.run(arguments: arguments)
            }.value
            busy.remove(request.id)
            finish(request, result: result)
            await refresh()
        }
    }

    private func finish(_ request: ActionRequest, result: Result<String, ActionRunnerError>) {
        switch result {
        case .success:
            log(request.logTitle, note: request.commandPreview, kind: .action, tone: .good)
            let undo = request.undo.map { undo in
                ActionRequest(
                    id: "undo:\(request.id)", action: undo.action, targets: request.targets,
                    logTitle: "Started \(request.targets.joined(separator: ", ")) again",
                    doneText: "\(request.targets.joined(separator: ", ")) started"
                )
            }
            show(Toast(text: request.doneText, success: true, undo: undo))
        case .failure(let error):
            measuring = false
            log("Failed: \(request.logTitle)", note: error.message, kind: .action, tone: .critical)
            show(Toast(text: error.message, success: false))
        }
    }

    func show(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func holdToast() {
        toastTask?.cancel()
    }

    func releaseToast() {
        guard let toast else { return }
        show(toast)
    }
}
