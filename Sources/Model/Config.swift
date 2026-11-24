import FossifyCommons
import Foundation
import Observation

/// Port of the clock Config (SharedPreferences -> UserDefaults); colors, the 24-hour
/// format, the first day of the week and the snooze settings live in FossifyCommons.
@Observable
final class Config {
    static let shared = Config()

    @ObservationIgnored private let d = UserDefaults.standard

    // Commons BaseConfig values the clock uses
    var preventPhoneFromSleeping: Bool { didSet { d.set(preventPhoneFromSleeping, forKey: "prevent_phone_from_sleeping") } }
    var defaultTab: Int { didSet { d.set(defaultTab, forKey: "default_tab") } }
    var lastUsedViewPagerPage: Int { didSet { d.set(lastUsedViewPagerPage, forKey: "last_used_view_pager_page") } }

    // Clock tab
    var selectedTimeZones: Set<String> { didSet { d.set(Array(selectedTimeZones), forKey: "selected_time_zones") } }
    var editedTimeZoneTitles: Set<String> { didSet { d.set(Array(editedTimeZoneTitles), forKey: "edited_time_zone_titles") } }

    // Alarm tab
    var alarmMaxReminderSecs: Int { didSet { d.set(alarmMaxReminderSecs, forKey: "alarm_max_reminder_secs") } }
    var increaseVolumeGradually: Bool { didSet { d.set(increaseVolumeGradually, forKey: "increase_volume_gradually") } }
    var alarmSort: Int { didSet { d.set(alarmSort, forKey: "alarms_sort_by") } }
    var alarmsCustomSorting: String { didSet { d.set(alarmsCustomSorting, forKey: "alarms_custom_sorting") } }

    // Timer tab
    var timerSeconds: Int { didSet { d.set(timerSeconds, forKey: "timer_seconds") } }
    var timerVibrate: Bool { didSet { d.set(timerVibrate, forKey: "timer_vibrate") } }
    var timerSoundUri: String { didSet { d.set(timerSoundUri, forKey: "timer_sound_uri") } }
    var timerSoundTitle: String { didSet { d.set(timerSoundTitle, forKey: "timer_sound_title") } }
    var timerMaxReminderSecs: Int { didSet { d.set(timerMaxReminderSecs, forKey: "timer_max_reminder_secs") } }
    var timerLabel: String? { didSet { d.set(timerLabel, forKey: "timer_label") } }
    var timerSort: Int { didSet { d.set(timerSort, forKey: "timers_sort_by") } }
    var timersCustomSorting: String { didSet { d.set(timersCustomSorting, forKey: "timers_custom_sorting") } }

    // Stopwatch tab
    var stopwatchLapsSort: Int { didSet { d.set(stopwatchLapsSort, forKey: "stopwatch_laps_sort_by") } }
    var toggleStopwatch: Bool { didSet { d.set(toggleStopwatch, forKey: "toggle_stopwatch") } }

    var lastDataExportPath: String { didSet { d.set(lastDataExportPath, forKey: "last_alarms_export_path") } }

    private init() {
        preventPhoneFromSleeping = d.object(forKey: "prevent_phone_from_sleeping") as? Bool ?? true
        defaultTab = d.object(forKey: "default_tab") as? Int ?? ClockConstants.tabLastUsed
        lastUsedViewPagerPage = d.object(forKey: "last_used_view_pager_page") as? Int ?? 0
        selectedTimeZones = Set(d.stringArray(forKey: "selected_time_zones") ?? [])
        editedTimeZoneTitles = Set(d.stringArray(forKey: "edited_time_zone_titles") ?? [])
        alarmMaxReminderSecs = d.object(forKey: "alarm_max_reminder_secs") as? Int ?? ClockConstants.defaultMaxAlarmReminderSecs
        increaseVolumeGradually = d.object(forKey: "increase_volume_gradually") as? Bool ?? true
        alarmSort = d.object(forKey: "alarms_sort_by") as? Int ?? ClockConstants.sortByCreationOrder
        alarmsCustomSorting = d.string(forKey: "alarms_custom_sorting") ?? ""
        timerSeconds = d.object(forKey: "timer_seconds") as? Int ?? 300
        timerVibrate = d.bool(forKey: "timer_vibrate")
        timerSoundUri = d.string(forKey: "timer_sound_uri") ?? AlarmSound.defaultURI
        timerSoundTitle = d.string(forKey: "timer_sound_title") ?? AlarmSound.defaultSound.title
        timerMaxReminderSecs = d.object(forKey: "timer_max_reminder_secs") as? Int ?? ClockConstants.defaultMaxTimerReminderSecs
        timerLabel = d.string(forKey: "timer_label")
        timerSort = d.object(forKey: "timers_sort_by") as? Int ?? ClockConstants.sortByCreationOrder
        timersCustomSorting = d.string(forKey: "timers_custom_sorting") ?? ""
        stopwatchLapsSort = d.object(forKey: "stopwatch_laps_sort_by") as? Int ?? (ClockConstants.sortByLap | ClockConstants.sortDescending)
        toggleStopwatch = d.bool(forKey: "toggle_stopwatch")
        lastDataExportPath = d.string(forKey: "last_alarms_export_path") ?? ""
    }

    // MARK: last used alarm / timer (EditAlarmDialog.restoreLastAlarm, EditTimerDialog.restoreLastAlarm)

    var alarmLastConfig: Alarm? {
        get { d.string(forKey: "alarm_last_config")?.data(using: .utf8).flatMap { try? JSONDecoder().decode(Alarm.self, from: $0) } }
        set { d.set((try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }, forKey: "alarm_last_config") }
    }

    var timerLastConfig: ClockTimer? {
        get { d.string(forKey: "timer_last_config")?.data(using: .utf8).flatMap { try? JSONDecoder().decode(ClockTimer.self, from: $0) } }
        set { d.set((try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) }, forKey: "timer_last_config") }
    }

    // MARK: time zones (Context.getEditedTimeZonesMap / getAllTimeZonesModified)

    var editedTimeZonesMap: [Int: String] {
        var map: [Int: String] = [:]
        for entry in editedTimeZoneTitles {
            let parts = entry.split(separator: Character(ClockConstants.editedTimeZoneSeparator), maxSplits: 1)
            if parts.count == 2, let id = Int(parts[0]) { map[id] = String(parts[1]) }
        }
        return map
    }

    var allTimeZonesModified: [MyTimeZone] {
        let edited = editedTimeZonesMap
        return TimeZones.all.map { tz in
            var tz = tz
            if let title = edited[tz.id] {
                tz.title = title
            } else if let space = tz.title.firstIndex(of: " ") {
                tz.title = String(tz.title[space...]).trimmingCharacters(in: .whitespaces)
            }
            return tz
        }
    }

    func modifiedTimeZoneTitle(_ id: Int) -> String {
        allTimeZonesModified.first { $0.id == id }?.title ?? TimeZones.defaultTitle(id)
    }

    /// EditTimeZoneDialog.dialogConfirmed().
    func setTimeZoneTitle(_ id: Int, _ title: String) {
        var map = editedTimeZonesMap
        if title.isEmpty { map[id] = nil } else { map[id] = title }
        editedTimeZoneTitles = Set(map.map { "\($0.key)\(ClockConstants.editedTimeZoneSeparator)\($0.value)" })
    }
}
