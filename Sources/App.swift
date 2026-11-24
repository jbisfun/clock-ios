import FossifyCommons
import Observation
import SwiftUI
import UIKit

enum Route: Hashable {
    case settings
    case customizeColors
    case about
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func push(_ r: Route) { path.append(r) }
}

/// The whole app as one view: the standalone app's window content, and what
/// the launcher presents.
public struct ClockRoot: View {
    @State private var router = Router()

    public init() {
        ClockNotifications.install()
    }

    public var body: some View {
        RootView()
            .environment(router)
            .environment(Config.shared)
            .environment(ClockStore.shared)
            .environment(Stopwatch.shared)
            .fossifyTheme()
    }
}

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(ClockStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var didLaunch = false

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        NavigationStack(path: $router.path) {
            MainView()
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .settings: SettingsView()
                        case .customizeColors: CustomizeColorsView()
                        case .about: AboutView(app: .clock)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .paletteBackground()
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .toast($store.toast)
        .fullScreenCover(item: $store.ringingAlarm) { alarm in
            AlarmRingingView(alarm: alarm).fossifyTheme()
        }
        .sheet(item: Binding(get: { store.snoozePickerAlarmID.map(IdentifiedInt.init) }, set: { store.snoozePickerAlarmID = $0?.id })) { item in
            // SnoozeReminderActivity
            SnoozePicker(alarmID: item.id)
        }
        .onAppear(perform: launch)
        .onChange(of: phase) { _, p in
            updateIdleTimer()
            if p == .active { store.reconcile() }
        }
        .onChange(of: config.preventPhoneFromSleeping) { updateIdleTimer() }
        .onChange(of: store.ringingAlarm) { updateIdleTimer() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// MainActivity.onCreate(): reschedule alarms, check the notification permission.
    private func launch() {
        updateIdleTimer()
        guard !didLaunch else { return }
        didLaunch = true
        guard store.alarms.contains(where: \.isEnabled) else { return }
        Task {
            let granted = await AlarmScheduler.requestAlarmPermission()
            store.rescheduleEnabledAlarms()
            if !granted {
                store.toast = "Notifications of this application are disabled. Please go in your device settings for enabling them."
            }
        }
    }

    /// FLAG_KEEP_SCREEN_ON while the app is in front (and always while an alarm rings).
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = phase == .active && (config.preventPhoneFromSleeping || store.ringingAlarm != nil)
    }
}

struct IdentifiedInt: Identifiable {
    let id: Int
}

/// SnoozeReminderActivity: pick the snooze time, cancelling stops the alarm.
struct SnoozePicker: View {
    @Environment(ClockStore.self) private var store
    let alarmID: Int

    var body: some View {
        PickSecondsDialog(curSeconds: ReminderConfig.shared.snoozeTime * 60, isSnoozePicker: true,
                          onCancel: { store.stopAlarm(alarmID) }) { seconds in
            ReminderConfig.shared.snoozeTime = seconds / 60
            store.snoozeAlarm(alarmID, minutes: ReminderConfig.shared.snoozeTime)
        }
    }
}
