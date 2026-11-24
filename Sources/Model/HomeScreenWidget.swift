import FossifyCommons
import Foundation

/// Publishes the next alarm and the 24-hour setting for the iOS home-screen clock widgets
/// (fossify-ios/widgets-ios). The time itself is drawn by WidgetKit (Text(.time) / timeline).
public enum ClockWidgetData {
    static let snapshotName = "clock"

    /// Call once at launch (LauncherApp.init): publishes now and whenever the alarms change.
    @MainActor
    public static func install() {
        WidgetBridge.track { publish() }
    }

    /// `fossify://open/clock`: the app opens on its current tab.
    @MainActor
    public static func handle(_ url: URL) {}

    @MainActor
    static func publish() {
        let store = ClockStore.shared
        let now = Date()
        let next = store.alarms.filter(\.isEnabled).compactMap { ClockTime.nextAlarm($0) }.filter { $0 > now }.min()
        let snapshot = ClockWidgetSnapshot(nextAlarm: store.closestEnabledAlarmString, nextAlarmDate: next,
                                           use24Hour: DateTimeFormat.shared.use24HourFormat)
        WidgetBridge.save(snapshot, snapshotName, reload: WidgetKinds.clock)
    }
}
