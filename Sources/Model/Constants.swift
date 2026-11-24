import Foundation
import FossifyCommons

/// helpers/Constants.kt.
enum ClockConstants {
    // Tabs (OPEN_TAB values; TAB_LAST_USED = 0 comes from commons)
    static let tabLastUsed = 0

    // Stopwatch sorting
    static let sortByLap = 1
    static let sortByLapTime = 2
    static let sortByTotalTime = 4
    static let sortDescending = 1024
    static let stopwatchLiveLapID = Int.max

    // Alarm and timer sorting
    static let sortByCreationOrder = 0
    static let sortByAlarmTime = 1
    static let sortByDateAndTime = 2
    static let sortByTimerDuration = 3
    static let sortByCustom = 131072
    static let sortByDateCreated = 262144

    static let todayBit = -1
    static let tomorrowBit = -2

    static let defaultAlarmMinutes = 480
    static let defaultMaxAlarmReminderSecs = 300
    static let defaultMaxTimerReminderSecs = 60
    static let editedTimeZoneSeparator = ":"
    static let exportFileName = "alarms_and_timers"
}

/// The four main tabs (TAB_CLOCK ... TAB_TIMER bits, view pager indexes).
enum ClockTab: Int, CaseIterable, Identifiable {
    case clock = 0, alarm, stopwatch, timer

    var id: Int { rawValue }
    /// OPEN_TAB / default_tab value.
    var bit: Int { 1 << rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .alarm: return "Alarm"
        case .stopwatch: return "Stopwatch"
        case .timer: return "Timer"
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case .clock: return selected ? "clock.fill" : "clock"
        case .alarm: return selected ? "alarm.fill" : "alarm"
        case .stopwatch: return selected ? "stopwatch.fill" : "stopwatch"
        case .timer: return selected ? "hourglass.bottomhalf.filled" : "hourglass"
        }
    }
}

enum ClockTime {
    static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                         "October", "November", "December"]

    /// getCurrentDayMinutes().
    static func currentDayMinutes(_ now: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// getTodayBit() / getTomorrowBit().
    static func todayBit() -> Int { 1 << WeekDays.index(ofCalendarWeekday: Calendar.current.component(.weekday, from: Date())) }
    static func tomorrowBit() -> Int {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return 1 << WeekDays.index(ofCalendarWeekday: Calendar.current.component(.weekday, from: tomorrow))
    }

    /// getTimeOfNextAlarm(): the next time the alarm rings after `now`.
    static func nextAlarm(minutes: Int, days: Int, after now: Date = Date()) -> Date? {
        let cal = Calendar.current
        guard var next = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now) else { return nil }
        switch days {
        case ClockConstants.todayBit: return next
        case ClockConstants.tomorrowBit: return cal.date(byAdding: .day, value: 1, to: next)
        default:
            for _ in 0..<8 {
                let day = WeekDays.index(ofCalendarWeekday: cal.component(.weekday, from: next))
                if days & (1 << day) != 0 && now < next { return next }
                next = cal.date(byAdding: .day, value: 1, to: next) ?? next
                next = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: next) ?? next
            }
            return nil
        }
    }

    static func nextAlarm(_ alarm: Alarm, after now: Date = Date()) -> Date? {
        nextAlarm(minutes: alarm.timeInMinutes, days: alarm.days, after: now)
    }

    /// updateNonRecurringAlarmDay().
    static func updateNonRecurringDay(_ alarm: inout Alarm) {
        guard !alarm.isRecurring() else { return }
        alarm.days = alarm.timeInMinutes > currentDayMinutes() ? ClockConstants.todayBit : ClockConstants.tomorrowBit
    }

    /// formatTime().
    static func formatTime(showSeconds: Bool, use24HourFormat: Bool, hours: Int, minutes: Int, seconds: Int) -> String {
        let h = use24HourFormat ? String(format: "%02d", hours) : "\(hours)"
        return showSeconds ? String(format: "%@:%02d:%02d", h, minutes, seconds) : String(format: "%@:%02d", h, minutes)
    }

    /// getFormattedTime(): (time, " AM"/" PM" suffix for the 12-hour format).
    static func formatted(passedSeconds: Int, showSeconds: Bool) -> (String, String?) {
        let hours = (passedSeconds / 3600) % 24, minutes = (passedSeconds / 60) % 60, seconds = passedSeconds % 60
        if DateTimeFormat.shared.use24HourFormat {
            return (formatTime(showSeconds: showSeconds, use24HourFormat: true, hours: hours, minutes: minutes, seconds: seconds), nil)
        }
        let h12 = hours == 0 || hours == 12 ? 12 : hours % 12
        return (formatTime(showSeconds: showSeconds, use24HourFormat: false, hours: h12, minutes: minutes, seconds: seconds),
                hours >= 12 ? " PM" : " AM")
    }

    static func formattedString(passedSeconds: Int, showSeconds: Bool) -> String {
        let (t, ampm) = formatted(passedSeconds: passedSeconds, showSeconds: showSeconds)
        return t + (ampm ?? "")
    }

    /// Seconds since midnight in a time zone.
    static func passedSeconds(_ date: Date = Date(), in zone: TimeZone = .current) -> Int {
        var cal = Calendar.current
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }

    /// getFormattedDate(): "Mon, 5 January".
    static func formattedDate(_ date: Date = Date(), in zone: TimeZone = .current) -> String {
        var cal = Calendar.current
        cal.timeZone = zone
        let c = cal.dateComponents([.weekday, .day, .month], from: date)
        let day = WeekDays.shortNames[WeekDays.index(ofCalendarWeekday: c.weekday ?? 2)]
        return "\(day), \(c.day ?? 1) \(months[(c.month ?? 1) - 1])"
    }

    /// Long.formatStopwatchTime().
    static func stopwatch(_ ms: Int64, longerMS: Bool) -> String {
        let hours = ms / 3_600_000, minutes = ms / 60000 % 60, seconds = ms / 1000 % 60
        var fraction = ms % 1000
        if !longerMS { fraction /= 100 }
        let f = longerMS ? String(format: "%03d", fraction) : "\(fraction)"
        if hours > 0 { return String(format: "%02d:%02d:%02d.", hours, minutes, seconds) + f }
        if minutes > 0 { return String(format: "%02d:%02d.", minutes, seconds) + f }
        return "\(seconds)." + f
    }

    /// Long.getFormattedDuration(): milliseconds rounded to seconds.
    static func duration(ms: Int64) -> String { Int((Double(ms) / 1000).rounded()).formattedDuration() }

    /// showRemainingTimeMessage().
    static func remainingTimeMessage(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let text = total >= 60 ? DurationStrings.minutes(Int((Double(total) / 60).rounded(.up))) : DurationStrings.seconds(total)
        return "Time remaining:\n\(text)"
    }
}

/// getAllTimeZones().
enum TimeZones {
    static let all: [MyTimeZone] = [
        .init(id: 1, title: "GMT-11:00 Midway", zoneName: "Pacific/Midway"),
        .init(id: 2, title: "GMT-10:00 Honolulu", zoneName: "Pacific/Honolulu"),
        .init(id: 3, title: "GMT-09:00 Anchorage", zoneName: "America/Anchorage"),
        .init(id: 4, title: "GMT-08:00 Los Angeles", zoneName: "America/Los_Angeles"),
        .init(id: 5, title: "GMT-08:00 Tijuana", zoneName: "America/Tijuana"),
        .init(id: 6, title: "GMT-07:00 Phoenix", zoneName: "America/Phoenix"),
        .init(id: 7, title: "GMT-07:00 Chihuahua", zoneName: "America/Chihuahua"),
        .init(id: 8, title: "GMT-07:00 Denver", zoneName: "America/Denver"),
        .init(id: 9, title: "GMT-06:00 Costa Rica", zoneName: "America/Costa_Rica"),
        .init(id: 10, title: "GMT-06:00 Chicago", zoneName: "America/Chicago"),
        .init(id: 11, title: "GMT-06:00 Mexico City", zoneName: "America/Mexico_City"),
        .init(id: 12, title: "GMT-06:00 Regina", zoneName: "America/Regina"),
        .init(id: 13, title: "GMT-05:00 Bogota", zoneName: "America/Bogota"),
        .init(id: 14, title: "GMT-05:00 New York", zoneName: "America/New_York"),
        .init(id: 15, title: "GMT-04:00 Caracas", zoneName: "America/Caracas"),
        .init(id: 16, title: "GMT-04:00 Barbados", zoneName: "America/Barbados"),
        .init(id: 17, title: "GMT-04:00 Halifax", zoneName: "America/Halifax"),
        .init(id: 18, title: "GMT-04:00 Manaus", zoneName: "America/Manaus"),
        .init(id: 19, title: "GMT-03:30 St. John's", zoneName: "America/St_Johns"),
        .init(id: 20, title: "GMT-03:00 Santiago", zoneName: "America/Santiago"),
        .init(id: 21, title: "GMT-03:00 Recife", zoneName: "America/Recife"),
        .init(id: 22, title: "GMT-03:00 Sao Paulo", zoneName: "America/Sao_Paulo"),
        .init(id: 23, title: "GMT-03:00 Buenos Aires", zoneName: "America/Buenos_Aires"),
        .init(id: 24, title: "GMT-03:00 Nuuk", zoneName: "America/Godthab"),
        .init(id: 25, title: "GMT-03:00 Montevideo", zoneName: "America/Montevideo"),
        .init(id: 26, title: "GMT-02:00 South Georgia", zoneName: "Atlantic/South_Georgia"),
        .init(id: 27, title: "GMT-01:00 Azores", zoneName: "Atlantic/Azores"),
        .init(id: 28, title: "GMT-01:00 Cape Verde", zoneName: "Atlantic/Cape_Verde"),
        .init(id: 29, title: "GMT+00:00 Casablanca", zoneName: "Africa/Casablanca"),
        .init(id: 30, title: "GMT+00:00 Greenwich Mean Time", zoneName: "Etc/Greenwich"),
        .init(id: 90, title: "GMT+00:00 London", zoneName: "Europe/London"),
        .init(id: 31, title: "GMT+01:00 Amsterdam", zoneName: "Europe/Amsterdam"),
        .init(id: 32, title: "GMT+01:00 Belgrade", zoneName: "Europe/Belgrade"),
        .init(id: 33, title: "GMT+01:00 Brussels", zoneName: "Europe/Brussels"),
        .init(id: 34, title: "GMT+01:00 Madrid", zoneName: "Europe/Madrid"),
        .init(id: 35, title: "GMT+01:00 Sarajevo", zoneName: "Europe/Sarajevo"),
        .init(id: 36, title: "GMT+01:00 Brazzaville", zoneName: "Africa/Brazzaville"),
        .init(id: 37, title: "GMT+02:00 Windhoek", zoneName: "Africa/Windhoek"),
        .init(id: 38, title: "GMT+02:00 Amman", zoneName: "Asia/Amman"),
        .init(id: 39, title: "GMT+02:00 Athens", zoneName: "Europe/Athens"),
        .init(id: 41, title: "GMT+02:00 Beirut", zoneName: "Asia/Beirut"),
        .init(id: 42, title: "GMT+02:00 Cairo", zoneName: "Africa/Cairo"),
        .init(id: 43, title: "GMT+02:00 Helsinki", zoneName: "Europe/Helsinki"),
        .init(id: 44, title: "GMT+02:00 Jerusalem", zoneName: "Asia/Jerusalem"),
        .init(id: 45, title: "GMT+02:00 Harare", zoneName: "Africa/Harare"),
        .init(id: 40, title: "GMT+03:00 Istanbul", zoneName: "Europe/Istanbul"),
        .init(id: 46, title: "GMT+03:00 Minsk", zoneName: "Europe/Minsk"),
        .init(id: 47, title: "GMT+03:00 Baghdad", zoneName: "Asia/Baghdad"),
        .init(id: 48, title: "GMT+03:00 Moscow", zoneName: "Europe/Moscow"),
        .init(id: 49, title: "GMT+03:00 Kuwait", zoneName: "Asia/Kuwait"),
        .init(id: 50, title: "GMT+03:00 Nairobi", zoneName: "Africa/Nairobi"),
        .init(id: 51, title: "GMT+03:30 Tehran", zoneName: "Asia/Tehran"),
        .init(id: 52, title: "GMT+04:00 Baku", zoneName: "Asia/Baku"),
        .init(id: 53, title: "GMT+04:00 Tbilisi", zoneName: "Asia/Tbilisi"),
        .init(id: 54, title: "GMT+04:00 Yerevan", zoneName: "Asia/Yerevan"),
        .init(id: 55, title: "GMT+04:00 Dubai", zoneName: "Asia/Dubai"),
        .init(id: 56, title: "GMT+04:30 Kabul", zoneName: "Asia/Kabul"),
        .init(id: 57, title: "GMT+05:00 Karachi", zoneName: "Asia/Karachi"),
        .init(id: 58, title: "GMT+05:00 Oral", zoneName: "Asia/Oral"),
        .init(id: 59, title: "GMT+05:00 Yekaterinburg", zoneName: "Asia/Yekaterinburg"),
        .init(id: 60, title: "GMT+05:30 Kolkata", zoneName: "Asia/Kolkata"),
        .init(id: 61, title: "GMT+05:30 Colombo", zoneName: "Asia/Colombo"),
        .init(id: 62, title: "GMT+05:45 Kathmandu", zoneName: "Asia/Kathmandu"),
        .init(id: 63, title: "GMT+06:00 Almaty", zoneName: "Asia/Almaty"),
        .init(id: 64, title: "GMT+06:30 Rangoon", zoneName: "Asia/Rangoon"),
        .init(id: 65, title: "GMT+07:00 Krasnoyarsk", zoneName: "Asia/Krasnoyarsk"),
        .init(id: 66, title: "GMT+07:00 Bangkok", zoneName: "Asia/Bangkok"),
        .init(id: 67, title: "GMT+07:00 Jakarta", zoneName: "Asia/Jakarta"),
        .init(id: 68, title: "GMT+08:00 Shanghai", zoneName: "Asia/Shanghai"),
        .init(id: 69, title: "GMT+08:00 Hong Kong", zoneName: "Asia/Hong_Kong"),
        .init(id: 70, title: "GMT+08:00 Irkutsk", zoneName: "Asia/Irkutsk"),
        .init(id: 71, title: "GMT+08:00 Kuala Lumpur", zoneName: "Asia/Kuala_Lumpur"),
        .init(id: 72, title: "GMT+08:00 Perth", zoneName: "Australia/Perth"),
        .init(id: 73, title: "GMT+08:00 Taipei", zoneName: "Asia/Taipei"),
        .init(id: 74, title: "GMT+09:00 Seoul", zoneName: "Asia/Seoul"),
        .init(id: 75, title: "GMT+09:00 Tokyo", zoneName: "Asia/Tokyo"),
        .init(id: 76, title: "GMT+09:00 Yakutsk", zoneName: "Asia/Yakutsk"),
        .init(id: 77, title: "GMT+09:30 Darwin", zoneName: "Australia/Darwin"),
        .init(id: 78, title: "GMT+10:00 Brisbane", zoneName: "Australia/Brisbane"),
        .init(id: 79, title: "GMT+10:00 Vladivostok", zoneName: "Asia/Vladivostok"),
        .init(id: 80, title: "GMT+10:00 Guam", zoneName: "Pacific/Guam"),
        .init(id: 81, title: "GMT+10:00 Magadan", zoneName: "Asia/Magadan"),
        .init(id: 82, title: "GMT+10:30 Adelaide", zoneName: "Australia/Adelaide"),
        .init(id: 83, title: "GMT+11:00 Hobart", zoneName: "Australia/Hobart"),
        .init(id: 84, title: "GMT+11:00 Sydney", zoneName: "Australia/Sydney"),
        .init(id: 85, title: "GMT+11:00 Noumea", zoneName: "Pacific/Noumea"),
        .init(id: 86, title: "GMT+12:00 Majuro", zoneName: "Pacific/Majuro"),
        .init(id: 87, title: "GMT+12:00 Fiji", zoneName: "Pacific/Fiji"),
        .init(id: 88, title: "GMT+13:00 Auckland", zoneName: "Pacific/Auckland"),
        .init(id: 89, title: "GMT+13:00 Tongatapu", zoneName: "Pacific/Tongatapu"),
    ]

    /// getDefaultTimeZoneTitle().
    static func defaultTitle(_ id: Int) -> String { all.first { $0.id == id }?.title ?? "" }
}
