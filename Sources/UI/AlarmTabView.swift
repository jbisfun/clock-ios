import FossifyCommons
import SwiftUI

/// AlarmFragment + AlarmsAdapter.
struct AlarmTabView: View {
    @Environment(Config.self) private var config
    @Environment(ClockStore.self) private var store
    @Environment(\.palette) private var palette
    @Binding var selection: Set<Int>
    @State private var editing: Alarm?
    @State private var warnToggle: (Int, Bool)?
    @State private var showWarning = false

    var body: some View {
        let alarms = store.sortedAlarms
        ZStack(alignment: .bottomTrailing) {
            if alarms.isEmpty {
                Placeholder(text: "No alarms found")
            } else {
                List {
                    ForEach(alarms) { alarm in
                        AlarmRow(alarm: alarm) { on in toggle(alarm, on) }
                            .selectable(selected: selection.contains(alarm.id), selecting: !selection.isEmpty,
                                        onTap: { editing = alarm }, onToggle: { selection.toggle(alarm.id) })
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(palette.backgroundColor)
                    }
                    // Drag handles in action mode (ItemMoveCallback) switch to the custom order.
                    .onMove { from, to in
                        var list = alarms
                        list.move(fromOffsets: from, toOffset: to)
                        store.saveAlarmsCustomOrder(list)
                    }
                    Color.clear.frame(height: 80).listRowBackground(palette.backgroundColor).listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(selection.isEmpty ? .inactive : .active))
            }
            if selection.isEmpty {
                Fab {
                    var alarm = store.createNewAlarm(minutes: ClockConstants.defaultAlarmMinutes, days: 0)
                    alarm.isEnabled = true
                    alarm.days = ClockTime.tomorrowBit()
                    editing = alarm
                }
            }
        }
        .sheet(item: $editing) { alarm in
            EditAlarmDialog(alarm: alarm) { saved in store.checkAlarmState(saved) }
        }
        .alert(alarmWarning, isPresented: $showWarning) {
            Button("OK") {
                ReminderConfig.shared.wasAlarmWarningShown = true
                if let (id, on) = warnToggle { store.alarmToggled(id, enabled: on) }
            }
        }
    }

    /// AlarmsAdapter.toggleAlarm().
    private func toggle(_ alarm: Alarm, _ on: Bool) {
        if alarm.isRecurring() && !ReminderConfig.shared.wasAlarmWarningShown {
            warnToggle = (alarm.id, on)
            showWarning = true
        } else {
            store.alarmToggled(alarm.id, enabled: on)
        }
    }
}

let alarmWarning = "Please make sure the alarm works properly before relying on it. It could misbehave due to system restrictions related to battery saving."

/// item_alarm.
struct AlarmRow: View {
    @Environment(\.palette) private var palette
    let alarm: Alarm
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                TimeText(passedSeconds: alarm.timeInMinutes * 60, size: 48)
                Text(daysString).font(.system(size: 16))
                if !alarm.label.isEmpty {
                    Text(alarm.label).font(.system(size: 16)).lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(palette.primaryColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// getAlarmSelectedDaysString().
    private var daysString: String {
        if alarm.isRecurring() {
            return alarm.days == WeekDays.everyDayBit ? "Every day" : WeekDays.shared.selectedDaysString(alarm.days)
        }
        if !alarm.isEnabled { return "Not scheduled" }
        return alarm.isToday() ? "Today" : "Tomorrow"
    }
}
