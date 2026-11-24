import FossifyCommons
import Foundation
import UserNotifications

/// The receivers (StopAlarmReceiver, SnoozeService, SkipUpcomingAlarmReceiver, HideTimerReceiver)
/// and the full-screen alarm intent, as a notification center delegate.
public enum ClockNotifications {
    /// Registers the notification actions and handlers with the shared `NotificationHub`.
    /// Call it at launch (the standalone app does; `ClockRoot` does it too).
    @MainActor
    public static func install() {
        AlarmScheduler.registerCategories()
        NotificationHub.register("clock", .init(willPresent: willPresent, didReceive: didReceive))
    }

    /// For hosts with their own delegate: the presentation options for a clock notification,
    /// nil if the notification is not the clock's.
    @MainActor
    public static func willPresent(_ notification: UNNotification) -> UNNotificationPresentationOptions? {
        let id = notification.request.identifier
        let info = notification.request.content.userInfo
        if id.hasPrefix("alarm-"), let alarmID = info["alarm_id"] as? Int {
            ClockStore.shared.onAlarmTriggered(alarmID)
            return []
        }
        if id.hasPrefix("timer-") { return [] }
        if id.hasPrefix("upcoming-") || id.hasPrefix("missed-") { return [.banner, .list] }
        return nil
    }

    /// For hosts with their own delegate: handles a response, false if it is not the clock's.
    @MainActor
    public static func didReceive(_ response: UNNotificationResponse) -> Bool {
        let request = response.notification.request
        let info = request.content.userInfo
        let store = ClockStore.shared
        let action = response.actionIdentifier
        if request.identifier.hasPrefix("alarm-"), let id = info["alarm_id"] as? Int {
            switch action {
            case AlarmScheduler.snoozeAction:
                let snooze = ReminderConfig.shared
                if snooze.useSameSnooze { store.snoozeAlarm(id, minutes: snooze.snoozeTime) } else { store.snoozePickerAlarmID = id }
            case AlarmScheduler.dismissAction, UNNotificationDismissActionIdentifier:
                store.stopAlarm(id)
            default:
                // Opening the notification shows the alarm screen while it may still ring.
                if -response.notification.date.timeIntervalSinceNow < Double(Config.shared.alarmMaxReminderSecs) {
                    store.onAlarmTriggered(id)
                } else {
                    store.stopAlarm(id)
                    store.requestedTab = .alarm
                }
            }
            return true
        }
        if request.identifier.hasPrefix("upcoming-"), let id = info["alarm_id"] as? Int {
            if action == AlarmScheduler.skipAction { store.skipNextOccurrence(id) } else { store.requestedTab = .alarm }
            return true
        }
        if request.identifier.hasPrefix("timer-"), let id = info["timer_id"] as? Int {
            if action == AlarmScheduler.timerDismissAction {
                store.resetTimer(id)
            } else {
                store.requestedTab = .timer
                store.requestedTimerID = id
            }
            return true
        }
        if request.identifier.hasPrefix("missed-") {
            store.requestedTab = .alarm
            return true
        }
        return false
    }
}
