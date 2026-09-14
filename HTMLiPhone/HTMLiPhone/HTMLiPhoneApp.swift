import SwiftUI

@main
@MainActor
struct HTMLiPhoneApp: App {
    @UIApplicationDelegateAdaptor(NotificationManager.self)
    private var notifications

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notifications)
        }
    }
}

@MainActor
private struct ContentView: View {
    @EnvironmentObject private var notifications: NotificationManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var showNotifications = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Button {
                    showNotifications = true
                } label: {
                    Label("الإشعارات", systemImage: "bell")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()

            HTMLPage()
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
                .environmentObject(notifications)
        }
        .task {
            await notifications.refresh()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task {
                    await notifications.refresh()
                }
            }
        }
    }
}
