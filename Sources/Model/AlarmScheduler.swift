import ActivityKit
import AlarmKit
import FossifyCommons
import SwiftUI
import UserNotifications

@available(iOS 26.0, *)
struct ClockAlarmMetadata: AlarmMetadata {}

/// The system side of AlarmController / setupAlarmClock / TimerService: alarms and
/// finished timers ring through AlarmKit (iOS 26+, when allowed) and otherwise through
/// time-sensitive local notifications; "upcoming alarm" and "missed alarm" notices are
/// always local notifications.
@MainActor
enum AlarmScheduler {
    static let alarmCategory = "clock.alarm"
    static let alarmPickSnoozeCategory = "clock.alarm.pick"
    static let upcomingCategory = "clock.upcoming"
    static let timerCategory = "clock.timer"
    static let snoozeAction = "clock.snooze"
    static let dismissAction = "clock.dismiss"
    static let skipAction = "clock.skip"
    static let timerDismissAction = "clock.timer.dismiss"

    private static var center: UNUserNotificationCenter { .current() }

    static func registerCategories() {
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze", options: [])
        let pickSnooze = UNNotificationAction(identifier: snoozeAction, title: "Snooze", options: [.foreground])
        let dismiss = UNNotificationAction(identifier: dismissAction, title: "Dismiss", options: [.destructive])
        let skip = UNNotificationAction(identifier: skipAction, title: "Dismiss", options: [])
        let timerDismiss = UNNotificationAction(identifier: timerDismissAction, title: "Dismiss", options: [])
        NotificationHub.setCategories("clock", [
            UNNotificationCategory(identifier: alarmCategory, actions: [snooze, dismiss], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: alarmPickSnoozeCategory, actions: [pickSnooze, dismiss], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: upcomingCategory, actions: [skip], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: timerCategory, actions: [timerDismiss], intentIdentifiers: [], options: []),
        ])
    }

    // MARK: Permissions

    /// handleNotificationPermission(): asks once, returns whether notifications may be shown.
    static func requestNotifications() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static var alarmKitAuthorized: Bool {
        if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .authorized }
        return false
    }

    /// handleFullScreenNotificationsPermission(): AlarmKit when available, else notifications.
    static func requestAlarmPermission() async -> Bool {
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: return true
            case .notDetermined:
                if (try? await AlarmManager.shared.requestAuthorization()) == .authorized { return true }
            default: break
            }
        }
        return await requestNotifications()
    }

    // MARK: Identifiers

    enum Kind: UInt64 { case alarm = 0xA, snooze = 0xB, timer = 0xC }

    static func uuid(_ kind: Kind, _ id: Int) -> UUID {
        UUID(uuidString: String(format: "C10C0000-0000-0000-%04llX-%012llX", kind.rawValue, UInt64(max(id, 0)))) ?? UUID()
    }

    private static func alarmRequestIDs(_ id: Int, snooze: Bool = true) -> [String] {
        ["alarm-\(id)", "upcoming-\(id)"] + (snooze ? ["alarm-\(id)-snooze"] : [])
            + (0..<7).flatMap { ["alarm-\(id)-\($0)", "upcoming-\(id)-\($0)"] }
    }

    // MARK: Alarms

    private static func title(_ alarm: Alarm) -> String { alarm.label.isEmpty ? "Alarm" : alarm.label }

    private static func alarmContent(_ alarm: Alarm) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title(alarm)
        c.body = ClockTime.formattedString(passedSeconds: alarm.timeInMinutes * 60, showSeconds: false)
        c.sound = alarm.sound.notificationSound
        c.categoryIdentifier = ReminderConfig.shared.useSameSnooze ? alarmCategory : alarmPickSnoozeCategory
        c.interruptionLevel = .timeSensitive
        c.userInfo = ["alarm_id": alarm.id]
        return c
    }

    private static func dateTrigger(_ date: Date) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    /// setupAlarmClock(): repeating alarms ring every selected weekday, the others once at `fixed`.
    static func schedule(_ alarm: Alarm, fixed: Date?) {
        cancel(alarm.id, snooze: false)
        if #available(iOS 26.0, *), alarmKitAuthorized {
            let schedule: AlarmKit.Alarm.Schedule
            if let fixed {
                schedule = .fixed(fixed)
            } else {
                let weekdays: [Locale.Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
                let days = (0..<7).filter { alarm.days & (1 << $0) != 0 }.map { weekdays[$0] }
                schedule = .relative(.init(time: .init(hour: alarm.timeInMinutes / 60, minute: alarm.timeInMinutes % 60), repeats: .weekly(days)))
            }
            let id = uuid(.alarm, alarm.id)
            let t = title(alarm), sound = alarm.sound
            Task { await kitSchedule(id: id, title: t, schedule: schedule, sound: sound, snooze: true) }
        } else if let fixed {
            center.add(UNNotificationRequest(identifier: "alarm-\(alarm.id)", content: alarmContent(alarm), trigger: dateTrigger(fixed)))
        } else {
            for day in 0..<7 where alarm.days & (1 << day) != 0 {
                var comps = DateComponents()
                comps.weekday = WeekDays.calendarWeekday(ofIndex: day)
                comps.hour = alarm.timeInMinutes / 60
                comps.minute = alarm.timeInMinutes % 60
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                center.add(UNNotificationRequest(identifier: "alarm-\(alarm.id)-\(day)", content: alarmContent(alarm), trigger: trigger))
            }
        }
        scheduleUpcoming(alarm, fixed: fixed)
    }

    /// UpcomingAlarmReceiver: a notice 10 minutes before the alarm, offering to skip it.
    private static func scheduleUpcoming(_ alarm: Alarm, fixed: Date?) {
        let c = UNMutableNotificationContent()
        c.title = "Upcoming alarm"
        c.categoryIdentifier = upcomingCategory
        c.userInfo = ["alarm_id": alarm.id]
        c.interruptionLevel = .passive
        if let fixed {
            c.body = ClockStore.alarmString(fixed)
            let early = fixed.addingTimeInterval(-600)
            let trigger: UNNotificationTrigger = early.timeIntervalSinceNow < 1
                ? UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false) : dateTrigger(early)
            center.add(UNNotificationRequest(identifier: "upcoming-\(alarm.id)", content: c, trigger: trigger))
            return
        }
        for day in 0..<7 where alarm.days & (1 << day) != 0 {
            guard let ring = ClockTime.nextAlarm(minutes: alarm.timeInMinutes, days: 1 << day) else { continue }
            c.body = ClockStore.alarmString(ring)
            let comps = Calendar.current.dateComponents([.weekday, .hour, .minute], from: ring.addingTimeInterval(-600))
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "upcoming-\(alarm.id)-\(day)", content: c, trigger: trigger))
        }
    }

    /// snoozeAlarm(): ring once more at `date`.
    static func scheduleSnooze(_ alarm: Alarm, at date: Date) {
        if #available(iOS 26.0, *), alarmKitAuthorized {
            let id = uuid(.snooze, alarm.id), t = title(alarm), sound = alarm.sound
            Task { await kitSchedule(id: id, title: t, schedule: .fixed(date), sound: sound, snooze: true) }
        } else {
            center.add(UNNotificationRequest(identifier: "alarm-\(alarm.id)-snooze", content: alarmContent(alarm), trigger: dateTrigger(date)))
        }
    }

    /// cancelAlarmClock().
    static func cancel(_ alarmID: Int, snooze: Bool = true) {
        center.removePendingNotificationRequests(withIdentifiers: alarmRequestIDs(alarmID, snooze: snooze))
        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.cancel(id: uuid(.alarm, alarmID))
            if snooze { try? AlarmManager.shared.cancel(id: uuid(.snooze, alarmID)) }
        }
    }

    static func removeDelivered(alarmID: Int) {
        center.removeDeliveredNotifications(withIdentifiers: alarmRequestIDs(alarmID))
    }

    /// AlarmNotificationHelper.postMissedAlarmNotification / postReplacedAlarmNotification.
    static func postMissed(_ alarm: Alarm, replaced: Bool) {
        let c = UNMutableNotificationContent()
        c.title = "Missed alarm"
        c.subtitle = ClockTime.formattedString(passedSeconds: alarm.timeInMinutes * 60, showSeconds: false)
        c.body = replaced ? "Replaced by another alarm" : "Alarm timed out"
        c.userInfo = ["open_tab": ClockTab.alarm.rawValue]
        center.add(UNNotificationRequest(identifier: "missed-\(alarm.id)", content: c, trigger: nil))
    }

    /// AlarmKit alarms still scheduled, counting down (snoozed) or ringing.
    static func activeKitAlarms() -> Set<UUID> {
        if #available(iOS 26.0, *) {
            return Set(((try? AlarmManager.shared.alarms) ?? []).map(\.id))
        }
        return []
    }

    /// AlarmKit alarms ringing or snoozed right now (rescheduling them would cut them off).
    static func busyKitAlarms() -> Set<UUID> {
        if #available(iOS 26.0, *) {
            return Set(((try? AlarmManager.shared.alarms) ?? []).filter { $0.state != .scheduled }.map(\.id))
        }
        return []
    }

    // MARK: Timers

    /// getTimerNotification(): rings when the timer runs out.
    static func scheduleTimer(_ timer: ClockTimer, end: Date) {
        guard let id = timer.id else { return }
        cancelTimer(id)
        let title = timer.label.isEmpty ? "Timer" : timer.label
        if #available(iOS 26.0, *), alarmKitAuthorized {
            let uid = uuid(.timer, id), sound = timer.sound
            Task { await kitSchedule(id: uid, title: title, schedule: .fixed(end), sound: sound, snooze: false) }
            return
        }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = "Time expired"
        c.sound = timer.sound.notificationSound
        c.categoryIdentifier = timerCategory
        c.interruptionLevel = .timeSensitive
        c.userInfo = ["timer_id": id]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: "timer-\(id)", content: c, trigger: trigger))
    }

    static func cancelTimer(_ id: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["timer-\(id)"])
        if #available(iOS 26.0, *) { try? AlarmManager.shared.cancel(id: uuid(.timer, id)) }
    }

    /// hideTimerNotification().
    static func hideTimerNotification(_ id: Int) {
        center.removeDeliveredNotifications(withIdentifiers: ["timer-\(id)"])
        if #available(iOS 26.0, *) { try? AlarmManager.shared.stop(id: uuid(.timer, id)) }
    }

    // MARK: AlarmKit

    @available(iOS 26.0, *)
    private static func kitSchedule(id: UUID, title: String, schedule: AlarmKit.Alarm.Schedule, sound: AlarmSound, snooze: Bool) async {
        let stop = AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "alarm.fill")
        let snoozeButton = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title), stopButton: stop,
                                            secondaryButton: snooze ? snoozeButton : nil,
                                            secondaryButtonBehavior: snooze ? .countdown : nil)
        let presentation = AlarmPresentation(alert: alert, countdown: snooze ? AlarmPresentation.Countdown(title: "Snooze") : nil)
        let attributes = AlarmAttributes<ClockAlarmMetadata>(presentation: presentation, metadata: ClockAlarmMetadata(),
                                                             tintColor: Color(argb: BaseConfig.shared.customPrimaryColor))
        let countdown = snooze ? AlarmKit.Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(ReminderConfig.shared.snoozeTime * 60)) : nil
        let alertSound: AlertConfiguration.AlertSound = sound.fileURL.map { .named($0.lastPathComponent) } ?? .default
        let config = AlarmManager.AlarmConfiguration<ClockAlarmMetadata>(countdownDuration: countdown, schedule: schedule,
                                                                        attributes: attributes, sound: alertSound)
        _ = try? await AlarmManager.shared.schedule(id: id, configuration: config)
    }
}
