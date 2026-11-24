import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// EditAlarmDialog.
struct EditAlarmDialog: View {
    @Environment(ClockStore.self) private var store
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var alarm: Alarm
    let onSave: (Alarm) -> Void
    @State private var pickTime = false
    @State private var pickSound = false
    @State private var showWarning = false

    init(alarm: Alarm, onSave: @escaping (Alarm) -> Void) {
        var a = alarm
        // restoreLastAlarm()
        if a.id == 0, let last = Config.shared.alarmLastConfig {
            a.label = last.label
            a.days = last.days
            a.soundTitle = last.soundTitle
            a.soundUri = last.soundUri
            a.timeInMinutes = last.timeInMinutes
            a.vibrate = last.vibrate
        }
        _alarm = State(initialValue: a)
        self.onSave = onSave
    }

    var body: some View {
        DialogFrame(title: nil) {
            VStack(spacing: 0) {
                Button { pickTime = true } label: {
                    TimeText(passedSeconds: alarm.timeInMinutes * 60, size: 60)
                }
                .buttonStyle(.plain)
                if !alarm.isRecurring() {
                    Text(alarm.timeInMinutes > ClockTime.currentDayMinutes() ? "(Today)" : "(Tomorrow)")
                        .font(.system(size: 18))
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                ForEach(WeekDays.shared.rotated(), id: \.self) { day in
                    let on = alarm.isRecurring() && alarm.days & (1 << day) != 0
                    Button { toggleDay(day) } label: {
                        Text(WeekDays.letters[day])
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(on ? palette.backgroundColor : palette.textColor)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(on ? palette.textColor : .clear))
                            .overlay(Circle().stroke(palette.textColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 16)
            Toggle(isOn: $alarm.vibrate) {
                Label("Vibrate", systemImage: "iphone.radiowaves.left.and.right").font(.system(size: 16))
            }
            .tint(palette.primaryColor)
            .padding(.vertical, 8)
            Button { pickSound = true } label: {
                Label(alarm.soundTitle, systemImage: "bell").font(.system(size: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                Image(systemName: "tag")
                TextField("Label", text: $alarm.label)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            }
            DialogButtons { save() }
        }
        .sheet(isPresented: $pickTime) {
            TimePickerDialog(minutes: alarm.timeInMinutes) { alarm.timeInMinutes = $0 }
        }
        .sheet(isPresented: $pickSound) {
            SelectAlarmSoundDialog(currentURI: alarm.soundUri, onPick: { sound in
                alarm.soundTitle = sound.title
                alarm.soundUri = sound.uri
            }, onDeleted: { sound in
                if alarm.soundUri == sound.uri {
                    alarm.soundTitle = AlarmSound.defaultSound.title
                    alarm.soundUri = AlarmSound.defaultURI
                }
                store.soundDeleted(sound)
            })
        }
        .alert(alarmWarning, isPresented: $showWarning) {
            Button("OK") {
                ReminderConfig.shared.wasAlarmWarningShown = true
                save()
            }
        }
    }

    private func toggleDay(_ day: Int) {
        if !alarm.isRecurring() { alarm.days = 0 }
        alarm.days ^= 1 << day
    }

    private func save() {
        guard ReminderConfig.shared.wasAlarmWarningShown else {
            showWarning = true
            return
        }
        var saved = alarm
        ClockTime.updateNonRecurringDay(&saved)
        saved.label = saved.label.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.isEnabled = true
        saved.oneShot = false
        saved.id = store.saveAlarm(saved)
        Config.shared.alarmLastConfig = saved
        onSave(saved)
        dismiss()
    }
}

/// TimePickerDialog / MaterialTimePicker.
struct TimePickerDialog: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Int) -> Void
    @State private var date: Date

    init(minutes: Int, onPick: @escaping (Int) -> Void) {
        self.onPick = onPick
        _date = State(initialValue: Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.locale, Locale(identifier: DateTimeFormat.shared.use24HourFormat ? "en_GB" : "en_US"))
            DialogButtons {
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                onPick((c.hour ?? 0) * 60 + (c.minute ?? 0))
                dismiss()
            }
        }
    }
}

/// EditTimerDialog.
struct EditTimerDialog: View {
    @Environment(ClockStore.self) private var store
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var timer: ClockTimer
    @State private var pickDuration = false
    @State private var pickSound = false

    init(timer: ClockTimer) {
        var t = timer
        // restoreLastAlarm()
        if t.id == nil, let last = Config.shared.timerLastConfig {
            t.label = last.label
            t.seconds = last.seconds
            t.soundTitle = last.soundTitle
            t.soundUri = last.soundUri
            t.vibrate = last.vibrate
        }
        _timer = State(initialValue: t)
    }

    var body: some View {
        DialogFrame(title: nil) {
            Button { pickDuration = true } label: {
                Label(timer.seconds.formattedDuration(), systemImage: "hourglass").font(.system(size: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle(isOn: Binding(get: { timer.vibrate }, set: { timer.vibrate = $0; timer.channelId = nil })) {
                Label("Vibrate", systemImage: "iphone.radiowaves.left.and.right").font(.system(size: 16))
            }
            .tint(palette.primaryColor)
            .padding(.vertical, 8)
            Button { pickSound = true } label: {
                Label(timer.soundTitle, systemImage: "bell").font(.system(size: 16))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                Image(systemName: "tag")
                TextField("Label", text: $timer.label)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            }
            DialogButtons {
                var saved = timer
                saved.label = saved.label.trimmingCharacters(in: .whitespacesAndNewlines)
                saved.id = store.saveTimer(saved)
                Config.shared.timerLastConfig = saved
                dismiss()
            }
        }
        .sheet(isPresented: $pickDuration) {
            DurationPickerDialog(initialSeconds: timer.seconds) { seconds in
                timer.seconds = seconds <= 0 ? 10 : seconds
            }
        }
        .sheet(isPresented: $pickSound) {
            SelectAlarmSoundDialog(currentURI: timer.soundUri, onPick: { sound in
                timer.soundTitle = sound.title
                timer.soundUri = sound.uri
                timer.channelId = nil
            }, onDeleted: { sound in
                if timer.soundUri == sound.uri {
                    timer.soundTitle = AlarmSound.defaultSound.title
                    timer.soundUri = AlarmSound.defaultURI
                }
                store.soundDeleted(sound)
            })
        }
    }
}

/// MyTimePickerDialogDialog: hours, minutes and seconds wheels.
struct DurationPickerDialog: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Int) -> Void
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int

    init(initialSeconds: Int, onPick: @escaping (Int) -> Void) {
        self.onPick = onPick
        _hours = State(initialValue: min(initialSeconds / 3600, 23))
        _minutes = State(initialValue: initialSeconds / 60 % 60)
        _seconds = State(initialValue: initialSeconds % 60)
    }

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            HStack(spacing: 0) {
                wheel($hours, 0..<24, "h")
                wheel($minutes, 0..<60, "m")
                wheel($seconds, 0..<60, "s")
            }
            DialogButtons {
                onPick(hours * 3600 + minutes * 60 + seconds)
                dismiss()
            }
        }
    }

    private func wheel(_ value: Binding<Int>, _ range: Range<Int>, _ unit: String) -> some View {
        Picker(unit, selection: value) {
            ForEach(range, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) { Text(unit).font(.system(size: 14)).padding(.trailing, 8) }
    }
}

/// AddTimeZonesDialog + SelectTimeZonesAdapter.
struct AddTimeZonesDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = Set(Config.shared.selectedTimeZones.compactMap { Int($0) })

    var body: some View {
        DialogFrame(title: nil) {
            ForEach(TimeZones.all) { zone in
                CheckRow(title: zone.title, on: Binding(get: { selected.contains(zone.id) }, set: { _ in selected.toggle(zone.id) }))
            }
            DialogButtons {
                config.selectedTimeZones = Set(selected.map { "\($0)" })
                dismiss()
            }
        }
    }
}

/// EditTimeZoneDialog.
struct EditTimeZoneDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let zone: MyTimeZone
    @State private var title: String
    @FocusState private var focused: Bool

    init(zone: MyTimeZone) {
        self.zone = zone
        _title = State(initialValue: Config.shared.modifiedTimeZoneTitle(zone.id))
    }

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            TextField("Title", text: $title)
                .focused($focused)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            Text(TimeZones.defaultTitle(zone.id))
                .font(.system(size: 14))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 8)
            DialogButtons {
                config.setTimeZoneTitle(zone.id, title.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            }
        }
        .onAppear { focused = true }
    }
}

/// ChangeAlarmSortDialog.
struct ChangeAlarmSortDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    @State private var sort = Config.shared.alarmSort

    var body: some View {
        SortDialog(sort: $sort, items: [
            (ClockConstants.sortByCreationOrder, "Creation order"),
            (ClockConstants.sortByAlarmTime, "Alarm time"),
            (ClockConstants.sortByDateAndTime, "Day and Alarm time"),
            (ClockConstants.sortByCustom, "Custom"),
        ]) {
            config.alarmSort = sort
            dismiss()
        }
    }
}

/// ChangeTimerSortDialog.
struct ChangeTimerSortDialog: View {
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    @State private var sort = Config.shared.timerSort

    var body: some View {
        SortDialog(sort: $sort, items: [
            (ClockConstants.sortByCreationOrder, "Creation order"),
            (ClockConstants.sortByTimerDuration, "Timer duration"),
            (ClockConstants.sortByCustom, "Custom"),
        ]) {
            config.timerSort = sort
            dismiss()
        }
    }
}

struct SortDialog: View {
    @Binding var sort: Int
    let items: [(Int, String)]
    let onOK: () -> Void

    var body: some View {
        DialogFrame(title: "Sort by") {
            ForEach(items, id: \.0) { item in
                Button { sort = item.0 } label: {
                    RadioRow(title: item.1, on: item.0 == sort || (item.0 == ClockConstants.sortByCreationOrder && !items.contains { $0.0 == sort }))
                }
                .buttonStyle(.plain)
            }
            DialogButtons(onOK: onOK)
        }
    }
}

/// ExportDataDialog: pick the file name, then the system exporter saves it.
struct ExportDataDialog: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onExport: (String) -> Void
    @State private var filename = "\(ClockConstants.exportFileName)_\(DateTimeFormat.format(Date(), "yyyy_MM_dd_HH_mm_ss"))"
    @State private var error: String?

    var body: some View {
        DialogFrame(title: "Export alarms and timers", scroll: false) {
            Text("Filename (without .json)").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
            TextField("", text: $filename)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            if let error {
                Text(error).font(.system(size: 14)).foregroundStyle(.red).padding(.top, 8)
            }
            DialogButtons {
                let name = filename.trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    error = "Please enter a name"
                } else if name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:*?\"<>|\0")) != nil {
                    error = "The name contains invalid characters"
                } else {
                    onExport(name)
                    dismiss()
                }
            }
        }
    }
}

/// The exported alarms_and_timers JSON.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
