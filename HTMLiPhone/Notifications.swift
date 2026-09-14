import SwiftUI
import UIKit
import UserNotifications
import Combine

struct ScheduledReminder: Identifiable {
    let id: String
    let title: String
    let body: String
    let date: Date
}

enum ReminderError: LocalizedError {
    case permissionDenied
    case emptyTitle
    case invalidDate
    case queueFull

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "اسمح بالإشعارات من إعدادات التطبيق أولًا."

        case .emptyTitle:
            return "أدخل عنوانًا للإشعار."

        case .invalidDate:
            return "اختر موعدًا بعد الوقت الحالي بخمس ثوانٍ على الأقل."

        case .queueFull:
            return "وصلت إلى حد التطبيق البالغ 60 إشعارًا مجدولًا. احذف بعض المواعيد أولًا."
        }
    }
}

@MainActor
final class NotificationManager:
    NSObject,
    UIApplicationDelegate,
    ObservableObject,
    UNUserNotificationCenterDelegate
{
    @Published private(set) var permission: UNAuthorizationStatus =
        .notDetermined

    @Published private(set) var pending: [ScheduledReminder] = []

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "htmliphone.reminder."

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        center.delegate = self
        return true
    }

    var permissionText: String {
        switch permission {
        case .notDetermined:
            return "لم يُطلب إذن الإشعارات بعد."

        case .denied:
            return "الإشعارات غير مسموح بها."

        case .authorized:
            return "إذن الإشعارات ممنوح."

        case .provisional:
            return "الإشعارات مسموح بها بهدوء."

        case .ephemeral:
            return "إذن الإشعارات ممنوح مؤقتًا."

        @unknown default:
            return "حالة الإذن غير معروفة."
        }
    }

    func refresh() async {
        let settings = await center.notificationSettings()
        permission = settings.authorizationStatus

        let requests = await center.pendingNotificationRequests()

        pending = requests.compactMap { request in
            guard request.identifier.hasPrefix(identifierPrefix),
                  let trigger =
                    request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate()
            else {
                return nil
            }

            return ScheduledReminder(
                id: request.identifier,
                title: request.content.title,
                body: request.content.body,
                date: date
            )
        }
        .sorted { $0.date < $1.date }
    }

    func requestPermission() async throws {
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try await center.requestAuthorization(
                options: [.alert, .sound]
            )
        }

        await refresh()

        switch permission {
        case .authorized, .provisional, .ephemeral:
            return

        default:
            throw ReminderError.permissionDenied
        }
    }

    func schedule(
        title: String,
        body: String,
        date: Date
    ) async throws {
        let cleanedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanedTitle.isEmpty else {
            throw ReminderError.emptyTitle
        }

        try await requestPermission()

        // Validate after permission handling, which can take some time.
        guard date.timeIntervalSinceNow > 5 else {
            throw ReminderError.invalidDate
        }

        let requests = await center.pendingNotificationRequests()

        // Keep a bounded queue so older reminders are not displaced.
        guard requests.count < 60 else {
            throw ReminderError.queueFull
        }

        let content = UNMutableNotificationContent()
        content.title = cleanedTitle
        content.body = body.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        content.sound = .default
        content.threadIdentifier = "local-reminders"

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

        components.calendar = Calendar.current
        components.timeZone = TimeZone.current

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        guard trigger.nextTriggerDate() != nil else {
            throw ReminderError.invalidDate
        }

        let request = UNNotificationRequest(
            identifier: identifierPrefix + UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try await center.add(request)
        await refresh()
    }

    func cancel(_ identifiers: [String]) async {
        let ownIdentifiers = identifiers.filter {
            $0.hasPrefix(identifierPrefix)
        }

        center.removePendingNotificationRequests(
            withIdentifiers: ownIdentifiers
        )

        center.removeDeliveredNotifications(
            withIdentifiers: ownIdentifiers
        )

        await refresh()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])

        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()

        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }
}

@MainActor
struct NotificationsView: View {
    @EnvironmentObject private var manager: NotificationManager
    @Environment(\.dismiss) private var dismiss

    @State private var notificationTitle = "تذكير"
    @State private var notificationBody = ""
    @State private var notificationDate =
        Date().addingTimeInterval(300)

    @State private var busy = false
    @State private var message = ""
    @State private var showMessage = false

    var body: some View {
        NavigationStack {
            Form {
                Section("الصلاحية") {
                    Text(manager.permissionText)

                    if manager.permission == .notDetermined {
                        Button("السماح بالإشعارات") {
                            Task {
                                await perform {
                                    try await manager.requestPermission()
                                }
                            }
                        }
                    } else {
                        Button("فتح إعدادات التطبيق") {
                            guard let url = URL(
                                string: UIApplication.openSettingsURLString
                            ) else {
                                return
                            }

                            UIApplication.shared.open(
                                url,
                                options: [:],
                                completionHandler: nil
                            )
                        }
                    }
                }

                Section("إشعار جديد") {
                    TextField(
                        "العنوان",
                        text: $notificationTitle
                    )

                    TextField(
                        "نص الإشعار",
                        text: $notificationBody,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    DatePicker(
                        "الموعد",
                        selection: $notificationDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Button {
                        Task {
                            await perform {
                                try await manager.schedule(
                                    title: notificationTitle,
                                    body: notificationBody,
                                    date: notificationDate
                                )

                                notificationBody = ""
                                notificationDate =
                                    Date().addingTimeInterval(300)

                                message = "تمت جدولة الإشعار."
                                showMessage = true
                            }
                        }
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Label(
                                "جدولة الإشعار",
                                systemImage: "bell.badge"
                            )
                        }
                    }
                    .disabled(
                        notificationTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }

                Section {
                    if manager.pending.isEmpty {
                        Text("لا توجد إشعارات مجدولة.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(manager.pending) { reminder in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(reminder.title)
                                .font(.headline)

                            if !reminder.body.isEmpty {
                                Text(reminder.body)
                            }

                            Text(
                                reminder.date,
                                format: .dateTime
                                    .year()
                                    .month()
                                    .day()
                                    .hour()
                                    .minute()
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        let identifiers = offsets.map {
                            manager.pending[$0].id
                        }

                        Task {
                            await manager.cancel(identifiers)
                        }
                    }
                } header: {
                    Text("الإشعارات المجدولة")
                } footer: {
                    Text("اسحب الإشعار لحذف موعده.")
                }
            }
            .disabled(busy)
            .navigationTitle("الإشعارات")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        dismiss()
                    }
                    .disabled(busy)
                }
            }
            .alert(
                "الإشعارات",
                isPresented: $showMessage
            ) {
                Button("حسنًا", role: .cancel) {}
            } message: {
                Text(message)
            }
            .task {
                await manager.refresh()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
    }

    private func perform(
        _ operation: () async throws -> Void
    ) async {
        guard !busy else {
            return
        }

        busy = true
        defer { busy = false }

        do {
            try await operation()
        } catch {
            message = error.localizedDescription
            showMessage = true
        }
    }
}
