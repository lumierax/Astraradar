import Foundation
import BackgroundTasks

final class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()
    static let identifier = "com.madar.swing.refresh"
    private var registered = false

    private init() {}

    func register() {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refreshTask)
        }
    }

    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()
        let operation = Task {
            let (config, notificationsEnabled) = await MainActor.run {
                (SettingsStore.shared.config, SettingsStore.shared.notifications)
            }
            do {
                let result = try await MarketScanner.shared.scan(config: config)
                if notificationsEnabled {
                    await NotificationManager.shared.notifyNewSignals(result.signals)
                }
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { operation.cancel() }
    }
}
