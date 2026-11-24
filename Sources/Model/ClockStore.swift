import AlarmKit
import FossifyCommons
import Foundation
import Observation
import UIKit
import UserNotifications

/// Alarms (DBHelper + AlarmController), timers (TimerDao + TimerHelper + the App's
/// CountDownTimers) and import/export, shared by the UI and the notification handler.
@MainActor
@Observable
final class ClockStore {
    static let shared = ClockStore()

    private(set) var alarms: [Alarm] = []
    private(set) var timers: [ClockTimer] = []
    var toast: String?
    /// AlarmActivity is showing this alarm.
    var ringingAlarm: Alarm?
    /// SnoozeReminderActivity: pick the snooze time for this alarm.
    var snoozePickerAlarmID: Int?
    /// OPEN_TAB requests from notifications.
    var requestedTab: ClockTab?
    var requestedTimerID: Int?
    var ringingTimerID: Int?

    @ObservationIgnored private let config = Config.shared
    @ObservationIgnored private let ringer = Ringer()
    @ObservationIgnored private var timerEngine: Task<Void, Never>?
    @ObservationIgnored private var timerHideTask: Task<Void, Never>?
    @ObservationIgnored private var kitUpdates: Task<Void, Never>?
    @ObservationIgnored private let d = UserDefaults.standard

    private static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Clock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var alarmsURL: URL { directory.appendingPathComponent("alarms.json") }
    private static var timersURL: URL { directory.appendingPathComponent("timers.json") }

    private init() {
        loadAlarms()
        loadTimers()
        startTimerEngine()
        observeAlarmKit()
    }

    // MARK: Persistence

    private func loadAlarms() {
        if let data = try? Data(contentsOf: Self.alarmsURL), let list = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = list
        } else {
            // DBHelper.insertInitialAlarms()
            var weekDays = createNewAlarm(minutes: 420, days: WeekDays.weekDaysBit)
            weekDays.id = nextAlarmID()
            var weekEnd = createNewAlarm(minutes: 540, days: WeekDays.weekendsBit)
            weekEnd.id = nextAlarmID()
            alarms = [weekDays, weekEnd]
            saveAlarms()
        }
    }

    private func saveAlarms() {
        if let data = try? JSONEncoder().encode(alarms) { try? data.write(to: Self.alarmsURL, options: .atomic) }
    }

    private func loadTimers() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: Self.timersURL), let list = try? decoder.decode([ClockTimer].self, from: data) {
            timers = list
        } else {
            // AppDatabase.insertDefaultTimer()
            var timer = createNewTimer()
            timer.id = nextTimerID()
            timers = [timer]
            saveTimers()
        }
    }

    private func saveTimers() {
        let encoder = JSONEncoder()
        encoder.userInfo[TimerState.storageKey] = true
        if let data = try? encoder.encode(timers) { try? data.write(to: Self.timersURL, options: .atomic) }
    }

    /// AUTOINCREMENT ids that are never reused.
    private func nextAlarmID() -> Int {
        let id = max(d.integer(forKey: "clock_next_alarm_id"), (alarms.map(\.id).max() ?? 0) + 1, 1)
        d.set(id + 1, forKey: "clock_next_alarm_id")
        return id
    }

    private func nextTimerID() -> Int {
        let id = max(d.integer(forKey: "clock_next_timer_id"), (timers.compactMap(\.id).max() ?? 0) + 1, 1)
        d.set(id + 1, forKey: "clock_next_timer_id")
        return id
    }

    /// Dates of alarms scheduled to ring once (one-time alarms, snoozes, skipped repeats).
    private var fixedFireDates: [Int: Date] {
        get {
            let raw = d.dictionary(forKey: "clock_fixed_fire_dates") as? [String: Double] ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, Date(timeIntervalSince1970: v)) } })
        }
        set { d.set(Dictionary(uniqueKeysWithValues: newValue.map { ("\($0.key)", $0.value.timeIntervalSince1970) }), forKey: "clock_fixed_fire_dates") }
    }

    // MARK: Alarms

    /// Context.createNewAlarm().
    func createNewAlarm(minutes: Int, days: Int) -> Alarm {
        Alarm(id: 0, timeInMinutes: minutes, days: days, isEnabled: false, vibrate: false,
              soundTitle: AlarmSound.defaultSound.title, soundUri: AlarmSound.defaultURI, label: "")
    }

    func alarm(_ id: Int) -> Alarm? { alarms.first { $0.id == id } }

    /// AlarmFragment.getSortedAlarms().
    var sortedAlarms: [Alarm] {
        switch config.alarmSort {
        case ClockConstants.sortByAlarmTime: return alarms.sorted { ($0.timeInMinutes, $0.id) < ($1.timeInMinutes, $1.id) }
        case ClockConstants.sortByDateCreated: return alarms.sorted { $0.id < $1.id }
        case ClockConstants.sortByDateAndTime:
            return alarms.sorted { (firstDayOrder($0.days), $0.timeInMinutes) < (firstDayOrder($1.days), $1.timeInMinutes) }
        case ClockConstants.sortByCustom:
            return Self.customOrder(alarms, config.alarmsCustomSorting) { $0.id }
        default: return alarms
        }
    }

    /// Context.firstDayOrder().
    private func firstDayOrder(_ bitMask: Int) -> Int {
        if bitMask == ClockConstants.todayBit { return -2 }
        if bitMask == ClockConstants.tomorrowBit { return -1 }
        for (i, day) in WeekDays.shared.rotated().enumerated() where bitMask & (1 << day) != 0 { return i }
        return bitMask
    }

    static func customOrder<T>(_ items: [T], _ order: String, id: (T) -> Int?) -> [T] {
        guard !order.isEmpty else { return items.sorted { (id($0) ?? 0) < (id($1) ?? 0) } }
        let ids = order.components(separatedBy: ", ").compactMap { Int($0) }
        let sorted = ids.compactMap { i in items.first { id($0) == i } }
        return sorted + items.filter { item in !ids.contains(id(item) ?? -1) }
    }

    func saveAlarmsCustomOrder(_ list: [Alarm]) {
        config.alarmsCustomSorting = list.map { "\($0.id)" }.joined(separator: ", ")
        if config.alarmSort != ClockConstants.sortByCustom { config.alarmSort = ClockConstants.sortByCustom }
    }

    /// DBHelper.insertAlarm() / updateAlarm(); returns the alarm id.
    @discardableResult
    func saveAlarm(_ alarm: Alarm) -> Int {
        var alarm = alarm
        if let i = alarms.firstIndex(where: { $0.id == alarm.id }), alarm.id != 0 {
            alarms[i] = alarm
        } else {
            alarm.id = nextAlarmID()
            alarms.append(alarm)
        }
        saveAlarms()
        return alarm.id
    }

    private func setEnabled(_ id: Int, _ enabled: Bool) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].isEnabled = enabled
        saveAlarms()
    }

    /// DBHelper.deleteAlarms().
    func deleteAlarms(_ ids: Set<Int>) {
        for alarm in alarms where ids.contains(alarm.id) && alarm.isEnabled { cancelAlarm(alarm) }
        alarms.removeAll { ids.contains($0.id) }
        saveAlarms()
    }

    /// AlarmFragment.alarmToggled() + checkAlarmState().
    func alarmToggled(_ id: Int, enabled: Bool) {
        guard var alarm = alarm(id) else { toast = "An unknown error occurred"; return }
        if !alarm.isRecurring() {
            ClockTime.updateNonRecurringDay(&alarm)
        }
        alarm.isEnabled = enabled
        saveAlarm(alarm)
        checkAlarmState(alarm)
        if !enabled && alarm.oneShot { deleteAlarms([id]) }
    }

    /// AlarmFragment.checkAlarmState().
    func checkAlarmState(_ alarm: Alarm) {
        if alarm.isEnabled {
            Task {
                if await AlarmScheduler.requestAlarmPermission() {
                    scheduleNextOccurrence(alarm, showToast: true)
                } else {
                    toast = "Notifications of this application are disabled. Please go in your device settings for enabling them."
                    scheduleNextOccurrence(alarm, showToast: false)
                }
            }
        } else {
            cancelAlarm(alarm)
        }
    }

    /// AlarmController.scheduleNextOccurrence().
    func scheduleNextOccurrence(_ alarm: Alarm, showToast: Bool = false, at fixed: Date? = nil) {
        guard let next = fixed ?? ClockTime.nextAlarm(alarm) else { return }
        var dates = fixedFireDates
        if alarm.isRecurring() && fixed == nil {
            AlarmScheduler.schedule(alarm, fixed: nil)
            dates[alarm.id] = nil
        } else {
            AlarmScheduler.schedule(alarm, fixed: next)
            dates[alarm.id] = next
        }
        fixedFireDates = dates
        if showToast { toast = ClockTime.remainingTimeMessage(next.timeIntervalSinceNow) }
    }

    func cancelAlarm(_ alarm: Alarm) {
        AlarmScheduler.cancel(alarm.id)
        var dates = fixedFireDates
        dates[alarm.id] = nil
        fixedFireDates = dates
    }

    /// AlarmController.rescheduleEnabledAlarms(), after settling alarms that rang while the app was away.
    func rescheduleEnabledAlarms() {
        reconcile()
        let dates = fixedFireDates
        let busy = AlarmScheduler.busyKitAlarms()
        for alarm in alarms where alarm.isEnabled && !busy.contains(AlarmScheduler.uuid(.alarm, alarm.id)) {
            if let date = dates[alarm.id], date > Date() {
                scheduleNextOccurrence(alarm, at: date)
            } else if !alarm.isToday() || alarm.timeInMinutes > ClockTime.currentDayMinutes() {
                scheduleNextOccurrence(alarm)
            }
        }
    }

    /// One-time alarms (and snoozes / skips) whose time has passed were stopped from the
    /// system alert: disable them like AlarmController.stopAlarm() and restore repeats.
    func reconcile() {
        let now = Date()
        let active = AlarmScheduler.activeKitAlarms()
        var dates = fixedFireDates
        for (id, date) in dates where date < now.addingTimeInterval(-1) {
            guard ringingAlarm?.id != id, let alarm = alarm(id) else {
                if alarm(id) == nil { dates[id] = nil }
                continue
            }
            if active.contains(AlarmScheduler.uuid(.alarm, id)) || active.contains(AlarmScheduler.uuid(.snooze, id)) { continue }
            dates[id] = nil
            fixedFireDates = dates
            if alarm.isEnabled {
                if alarm.isRecurring() { scheduleNextOccurrence(alarm) } else { disableOrDeleteOneTimeAlarm(alarm) }
            }
            dates = fixedFireDates
        }
        fixedFireDates = dates
    }

    /// AlarmController.disableOrDeleteOneTimeAlarm().
    private func disableOrDeleteOneTimeAlarm(_ alarm: Alarm) {
        AlarmScheduler.cancel(alarm.id)
        if alarm.oneShot {
            alarms.removeAll { $0.id == alarm.id }
            saveAlarms()
        } else {
            setEnabled(alarm.id, false)
        }
    }

    /// AlarmController.onAlarmTriggered() + AlarmService.startNewAlarm(): ring in the app.
    func onAlarmTriggered(_ id: Int) {
        guard let alarm = alarm(id) else { return }
        if let current = ringingAlarm {
            if current.id == id { return }
            AlarmScheduler.postMissed(current, replaced: true)
            stopAlarm(current.id)
        }
        ringingAlarm = alarm
        ringer.start(sound: alarm.sound, vibrate: alarm.vibrate, increaseVolume: config.increaseVolumeGradually,
                     maxSeconds: config.alarmMaxReminderSecs) { [weak self] in
            guard let self, self.ringingAlarm?.id == id else { return }
            AlarmScheduler.postMissed(alarm, replaced: false)
            self.stopAlarm(id)
        }
    }

    /// AlarmController.silenceAlarm().
    func silenceAlarm(_ id: Int) {
        if ringingAlarm?.id == id { ringer.stop() }
    }

    /// AlarmController.stopAlarm().
    func stopAlarm(_ id: Int) {
        if ringingAlarm?.id == id {
            ringer.stop()
            ringingAlarm = nil
        }
        AlarmScheduler.removeDelivered(alarmID: id)
        var dates = fixedFireDates
        let hadFixedDate = dates[id] != nil
        dates[id] = nil
        fixedFireDates = dates
        guard let alarm = alarm(id), alarm.isEnabled else { return }
        if !alarm.isRecurring() {
            disableOrDeleteOneTimeAlarm(alarm)
        } else if hadFixedDate {
            // A skipped repeat rang: back to the weekly schedule.
            scheduleNextOccurrence(alarm)
        }
    }

    /// AlarmController.snoozeAlarm().
    func snoozeAlarm(_ id: Int, minutes: Int) {
        if ringingAlarm?.id == id {
            ringer.stop()
            ringingAlarm = nil
        }
        AlarmScheduler.removeDelivered(alarmID: id)
        guard let alarm = alarm(id) else { return }
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        AlarmScheduler.scheduleSnooze(alarm, at: date)
        if !alarm.isRecurring() {
            var dates = fixedFireDates
            dates[id] = date
            fixedFireDates = dates
        }
    }

    /// AlarmController.skipNextOccurrence().
    func skipNextOccurrence(_ id: Int) {
        guard let alarm = alarm(id) else { return }
        AlarmScheduler.cancel(id)
        if alarm.isRecurring() {
            if let next = ClockTime.nextAlarm(alarm), let following = ClockTime.nextAlarm(alarm, after: next.addingTimeInterval(60)) {
                scheduleNextOccurrence(alarm, at: following)
            }
        } else {
            disableOrDeleteOneTimeAlarm(alarm)
        }
    }

    /// getClosestEnabledAlarmString(): "Tue 07:00".
    var closestEnabledAlarmString: String {
        let now = Date()
        let dates = fixedFireDates
        let next = alarms.filter(\.isEnabled).compactMap { alarm -> Date? in
            if !alarm.isRecurring(), let d = dates[alarm.id], d > now { return d }
            return ClockTime.nextAlarm(alarm)
        }.filter { $0 > now }.min()
        return next.map(Self.alarmString) ?? ""
    }

    static func alarmString(_ date: Date) -> String {
        let day = WeekDays.shortNames[WeekDays.index(ofCalendarWeekday: Calendar.current.component(.weekday, from: date))]
        let time = DateTimeFormat.format(date, DateTimeFormat.shared.use24HourFormat ? "HH:mm" : "h:mm a")
        return "\(day) \(time)"
    }

    // MARK: Timers

    /// Context.createNewTimer().
    func createNewTimer() -> ClockTimer {
        ClockTimer(id: nil, seconds: config.timerSeconds, state: .idle, vibrate: config.timerVibrate,
                   soundUri: config.timerSoundUri, soundTitle: config.timerSoundTitle, label: config.timerLabel ?? "",
                   createdAt: Int64(Date().timeIntervalSince1970 * 1000))
    }

    func timer(_ id: Int) -> ClockTimer? { timers.first { $0.id == id } }

    /// TimerFragment.getSortedTimers().
    var sortedTimers: [ClockTimer] {
        switch config.timerSort {
        case ClockConstants.sortByTimerDuration: return timers.sorted { ($0.seconds, $0.id ?? 0) < ($1.seconds, $1.id ?? 0) }
        case ClockConstants.sortByDateCreated: return timers.sorted { ($0.id ?? 0) < ($1.id ?? 0) }
        case ClockConstants.sortByCustom: return Self.customOrder(timers, config.timersCustomSorting) { $0.id }
        default: return timers
        }
    }

    func saveTimersCustomOrder(_ list: [ClockTimer]) {
        config.timersCustomSorting = list.compactMap { $0.id.map { "\($0)" } }.joined(separator: ", ")
        if config.timerSort != ClockConstants.sortByCustom { config.timerSort = ClockConstants.sortByCustom }
    }

    /// TimerDao.insertOrUpdateTimer().
    @discardableResult
    func saveTimer(_ timer: ClockTimer) -> Int {
        var timer = timer
        if let id = timer.id, let i = timers.firstIndex(where: { $0.id == id }) {
            // The edit dialog's copy may be stale; the countdown state stays the store's.
            timer.state = timers[i].state
            timers[i] = timer
        } else {
            timer.id = nextTimerID()
            timers.append(timer)
        }
        saveTimers()
        return timer.id ?? 0
    }

    private func updateTimerState(_ id: Int, _ state: TimerState) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        if timers[i].oneShot && state == .idle {
            timers.remove(at: i)
        } else {
            timers[i].state = state
        }
        saveTimers()
        startTimerEngine()
    }

    /// TimerEvent.Start.
    func startTimer(_ id: Int, durationMS: Int64) {
        guard let timer = timer(id) else { return }
        let end = Date().addingTimeInterval(TimeInterval(durationMS) / 1000)
        updateTimerState(id, .running(duration: durationMS, end: end))
        AlarmScheduler.scheduleTimer(timer, end: end)
    }

    /// TimerAdapter.toggleTimer().
    func toggleTimer(_ id: Int) {
        guard let timer = timer(id) else { return }
        switch timer.state {
        case .idle, .finished:
            stopTimerRinging(id)
            startTimer(id, durationMS: Int64(timer.seconds) * 1000)
        case .paused(_, let tick): startTimer(id, durationMS: tick)
        case .running(let duration, _):
            AlarmScheduler.cancelTimer(id)
            updateTimerState(id, .paused(duration: duration, tick: timer.state.tick))
        }
    }

    /// TimerEvent.Reset.
    func resetTimer(_ id: Int) {
        AlarmScheduler.cancelTimer(id)
        stopTimerRinging(id)
        AlarmScheduler.hideTimerNotification(id)
        updateTimerState(id, .idle)
    }

    /// TimerEvent.Delete.
    func deleteTimers(_ ids: Set<Int>) {
        for id in ids {
            AlarmScheduler.cancelTimer(id)
            AlarmScheduler.hideTimerNotification(id)
            stopTimerRinging(id)
        }
        timers.removeAll { ids.contains($0.id ?? -1) }
        saveTimers()
    }

    /// TimerEvent.Finish: ring in the app for timerMaxReminderSecs (the notification
    /// or AlarmKit alert covers the background).
    private func finishTimer(_ id: Int, ring: Bool) {
        guard let timer = timer(id) else { return }
        updateTimerState(id, .finished)
        guard ring, !AlarmScheduler.alarmKitAuthorized, UIApplication.shared.applicationState == .active else { return }
        ringingTimerID = id
        ringer.start(sound: timer.sound, vibrate: timer.vibrate, increaseVolume: false, maxSeconds: config.timerMaxReminderSecs) { [weak self] in
            self?.stopTimerRinging(id)
            AlarmScheduler.hideTimerNotification(id)
        }
    }

    private func stopTimerRinging(_ id: Int) {
        guard ringingTimerID == id else { return }
        ringer.stop()
        ringingTimerID = nil
    }

    /// The CountDownTimers: watch running timers and finish them on time.
    private func startTimerEngine() {
        guard timerEngine == nil, timers.contains(where: { $0.state.isRunning }) else { return }
        timerEngine = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let running = self.timers.filter { $0.state.isRunning }
                if running.isEmpty { self.timerEngine = nil; return }
                for timer in running {
                    if case .running(_, let end) = timer.state, end <= Date(), let id = timer.id {
                        self.finishTimer(id, ring: end > Date().addingTimeInterval(-2))
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // MARK: AlarmKit

    private func observeAlarmKit() {
        guard #available(iOS 26.0, *) else { return }
        kitUpdates = Task { [weak self] in
            for await _ in AlarmManager.shared.alarmUpdates {
                self?.reconcile()
            }
        }
    }

    // MARK: Import / export (ExportHelper, ImportHelper)

    func exportData() -> Data? {
        guard !alarms.isEmpty || !timers.isEmpty else {
            toast = "No entries for exporting have been found"
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try? encoder.encode(AlarmTimerBackup(alarms: alarms, timers: timers))
    }

    func importData(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let backup = try? JSONDecoder().decode(AlarmTimerBackup.self, from: data) else {
            toast = "No items found."
            return
        }
        var imported = 0
        for alarm in backup.alarms where !alarms.contains(where: {
            $0.timeInMinutes == alarm.timeInMinutes && $0.days == alarm.days && $0.vibrate == alarm.vibrate &&
                $0.soundTitle == alarm.soundTitle && $0.soundUri == alarm.soundUri && $0.label == alarm.label && $0.oneShot == alarm.oneShot
        }) {
            var a = alarm
            a.id = 0
            let id = saveAlarm(a)
            if a.isEnabled, let saved = self.alarm(id) { scheduleNextOccurrence(saved) }
            imported += 1
        }
        for timer in backup.timers where !timers.contains(where: {
            $0.seconds == timer.seconds && $0.vibrate == timer.vibrate && $0.soundUri == timer.soundUri &&
                $0.soundTitle == timer.soundTitle && $0.label == timer.label && $0.createdAt == timer.createdAt
        }) {
            var t = timer
            t.id = nil
            t.state = .idle
            saveTimer(t)
            imported += 1
        }
        toast = imported > 0 ? "Importing successful" : "No new entries for importing have been found"
    }

    // MARK: Sound deleted (checkAlarmsWithDeletedSoundUri)

    func soundDeleted(_ sound: AlarmSound) {
        for i in alarms.indices where alarms[i].soundUri == sound.uri {
            alarms[i].soundUri = AlarmSound.defaultURI
            alarms[i].soundTitle = AlarmSound.defaultSound.title
        }
        saveAlarms()
    }
}

