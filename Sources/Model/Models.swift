import Foundation
import FossifyCommons

/// models/Alarm.kt. Field names match the kotlinx JSON of the Android export.
struct Alarm: Codable, Identifiable, Hashable {
    var id: Int
    var timeInMinutes: Int
    var days: Int
    var isEnabled: Bool
    var vibrate: Bool
    var soundTitle: String
    var soundUri: String
    var label: String
    var oneShot: Bool = false

    func isRecurring() -> Bool { days > 0 }
    func isToday() -> Bool { days == ClockConstants.todayBit }
    func isTomorrow() -> Bool { days == ClockConstants.tomorrowBit }

    var sound: AlarmSound { AlarmSound(id: 0, title: soundTitle, uri: soundUri) }

    enum CodingKeys: String, CodingKey { case id, timeInMinutes, days, isEnabled, vibrate, soundTitle, soundUri, label, oneShot }

    init(id: Int, timeInMinutes: Int, days: Int, isEnabled: Bool, vibrate: Bool, soundTitle: String, soundUri: String,
         label: String, oneShot: Bool = false) {
        self.id = id
        self.timeInMinutes = timeInMinutes
        self.days = days
        self.isEnabled = isEnabled
        self.vibrate = vibrate
        self.soundTitle = soundTitle
        self.soundUri = soundUri
        self.label = label
        self.oneShot = oneShot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        timeInMinutes = try c.decode(Int.self, forKey: .timeInMinutes)
        days = try c.decode(Int.self, forKey: .days)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        vibrate = try c.decodeIfPresent(Bool.self, forKey: .vibrate) ?? false
        soundTitle = try c.decodeIfPresent(String.self, forKey: .soundTitle) ?? AlarmSound.defaultSound.title
        soundUri = try c.decodeIfPresent(String.self, forKey: .soundUri) ?? AlarmSound.defaultURI
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        oneShot = try c.decodeIfPresent(Bool.self, forKey: .oneShot) ?? false
    }
}

/// models/TimerState.kt. Android keeps the remaining `tick` updated by a CountDownTimer;
/// here a running timer stores its end date and the tick is derived from it.
enum TimerState: Codable, Hashable {
    case idle
    case running(duration: Int64, end: Date)
    case paused(duration: Int64, tick: Int64)
    case finished

    static let storageKey = CodingUserInfoKey(rawValue: "clock.storage")!
    private static let prefix = "org.fossify.clock.models.TimerState."

    /// Remaining milliseconds.
    var tick: Int64 {
        switch self {
        case .running(_, let end): return max(0, Int64(end.timeIntervalSinceNow * 1000))
        case .paused(_, let tick): return tick
        default: return 0
        }
    }

    var isRunning: Bool { if case .running = self { return true } else { return false } }

    enum CodingKeys: String, CodingKey { case type, duration, tick, end }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try c.decodeIfPresent(String.self, forKey: .type) ?? "").replacingOccurrences(of: TimerState.prefix, with: "")
        switch type {
        case "Running":
            let duration = try c.decodeIfPresent(Int64.self, forKey: .duration) ?? 0
            if let end = try c.decodeIfPresent(Double.self, forKey: .end) {
                self = .running(duration: duration, end: Date(timeIntervalSince1970: end))
            } else {
                let tick = try c.decodeIfPresent(Int64.self, forKey: .tick) ?? 0
                self = .paused(duration: duration, tick: tick)
            }
        case "Paused":
            self = .paused(duration: try c.decodeIfPresent(Int64.self, forKey: .duration) ?? 0,
                           tick: try c.decodeIfPresent(Int64.self, forKey: .tick) ?? 0)
        case "Finished": self = .finished
        default: self = .idle
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle: try c.encode(TimerState.prefix + "Idle", forKey: .type)
        case .finished: try c.encode(TimerState.prefix + "Finished", forKey: .type)
        case .running(let duration, let end):
            try c.encode(TimerState.prefix + "Running", forKey: .type)
            try c.encode(duration, forKey: .duration)
            try c.encode(tick, forKey: .tick)
            if encoder.userInfo[TimerState.storageKey] as? Bool == true {
                try c.encode(end.timeIntervalSince1970, forKey: .end)
            }
        case .paused(let duration, let tick):
            try c.encode(TimerState.prefix + "Paused", forKey: .type)
            try c.encode(duration, forKey: .duration)
            try c.encode(tick, forKey: .tick)
        }
    }
}

/// models/Timer.kt.
struct ClockTimer: Codable, Identifiable, Hashable {
    var id: Int?
    var seconds: Int
    var state: TimerState
    var vibrate: Bool
    var soundUri: String
    var soundTitle: String
    var label: String
    var createdAt: Int64
    var channelId: String?
    var oneShot: Bool = false

    var sound: AlarmSound { AlarmSound(id: 0, title: soundTitle, uri: soundUri) }

    enum CodingKeys: String, CodingKey { case id, seconds, state, vibrate, soundUri, soundTitle, label, createdAt, channelId, oneShot }

    init(id: Int?, seconds: Int, state: TimerState, vibrate: Bool, soundUri: String, soundTitle: String, label: String,
         createdAt: Int64, channelId: String? = nil, oneShot: Bool = false) {
        self.id = id
        self.seconds = seconds
        self.state = state
        self.vibrate = vibrate
        self.soundUri = soundUri
        self.soundTitle = soundTitle
        self.label = label
        self.createdAt = createdAt
        self.channelId = channelId
        self.oneShot = oneShot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        seconds = try c.decode(Int.self, forKey: .seconds)
        state = (try? c.decode(TimerState.self, forKey: .state)) ?? .idle
        vibrate = try c.decodeIfPresent(Bool.self, forKey: .vibrate) ?? false
        soundUri = try c.decodeIfPresent(String.self, forKey: .soundUri) ?? AlarmSound.defaultURI
        soundTitle = try c.decodeIfPresent(String.self, forKey: .soundTitle) ?? AlarmSound.defaultSound.title
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? Int64(Date().timeIntervalSince1970 * 1000)
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        oneShot = try c.decodeIfPresent(Bool.self, forKey: .oneShot) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(seconds, forKey: .seconds)
        try c.encode(state, forKey: .state)
        try c.encode(vibrate, forKey: .vibrate)
        try c.encode(soundUri, forKey: .soundUri)
        try c.encode(soundTitle, forKey: .soundTitle)
        try c.encode(label, forKey: .label)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(channelId, forKey: .channelId)
        try c.encode(oneShot, forKey: .oneShot)
    }
}

/// models/AlarmTimerBackup.kt (export / import file).
struct AlarmTimerBackup: Codable {
    var alarms: [Alarm]
    var timers: [ClockTimer]
}

/// models/Lap.kt.
struct Lap: Identifiable, Hashable {
    let id: Int
    var lapTime: Int64
    var totalTime: Int64

    var isLive: Bool { id == ClockConstants.stopwatchLiveLapID }

    static func sorted(_ laps: [Lap], by sorting: Int) -> [Lap] {
        let descending = sorting & ClockConstants.sortDescending != 0
        func key(_ l: Lap) -> Int64 {
            if sorting & ClockConstants.sortByLap != 0 { return Int64(l.id) }
            if sorting & ClockConstants.sortByLapTime != 0 { return l.lapTime }
            return l.totalTime
        }
        return laps.sorted { descending ? key($0) > key($1) : key($0) < key($1) }
    }
}

/// models/MyTimeZone.kt.
struct MyTimeZone: Identifiable, Hashable {
    let id: Int
    var title: String
    let zoneName: String
}
