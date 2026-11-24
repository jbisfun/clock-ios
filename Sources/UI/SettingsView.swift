import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// SettingsActivity.
struct SettingsView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(ClockStore.self) private var store
    @Environment(\.palette) private var palette

    @State private var defaultTab = false
    @State private var startWeekOn = false
    @State private var alarmMaxReminder = false
    @State private var snoozeTime = false
    @State private var timerMaxReminder = false
    @State private var exportName = false
    @State private var exporting = false
    @State private var exportDocument: BackupDocument?
    @State private var exportFilename = ""
    @State private var importing = false

    private let dateTime = DateTimeFormat.shared
    private let weekDays = WeekDays.shared
    private let reminders = ReminderConfig.shared

    var body: some View {
        @Bindable var config = config
        @Bindable var dateTime = dateTime
        @Bindable var reminders = reminders
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Text("General").sectionHeader(palette)
                    SettingsToggle("Use 24-hour time format", isOn: $dateTime.use24HourFormat)
                    SettingsItem("Tab to open at app start", value: defaultTabTitle) { defaultTab = true }
                    SettingsItem("Start week on", value: WeekDays.names[weekDays.firstDayOfWeek - 1]) { startWeekOn = true }
                    SettingsToggle("Prevent phone from sleeping while the app is in foreground", isOn: $config.preventPhoneFromSleeping)

                    Text("Alarm tab").sectionHeader(palette)
                    SettingsItem("Max reminder duration", value: DurationStrings.seconds(config.alarmMaxReminderSecs)) { alarmMaxReminder = true }
                    SettingsToggle("Increase volume gradually", isOn: $config.increaseVolumeGradually)
                    SettingsToggle("Always use same snooze time", isOn: $reminders.useSameSnooze)
                    if reminders.useSameSnooze {
                        SettingsItem("Snooze time", value: DurationStrings.minutes(reminders.snoozeTime)) { snoozeTime = true }
                    }

                    Text("Timer tab").sectionHeader(palette)
                    SettingsItem("Max reminder duration", value: DurationStrings.seconds(config.timerMaxReminderSecs)) { timerMaxReminder = true }

                    Text("Migrating").sectionHeader(palette)
                    SettingsItem("Export alarms and timers") { exportName = true }
                    SettingsItem("Import alarms and timers") { importing = true }
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $defaultTab) {
            RadioDialog(title: nil, items: ClockTab.allCases.map { ($0.bit, $0.title) } + [(ClockConstants.tabLastUsed, "Last used one")],
                        selected: config.defaultTab) { config.defaultTab = $0 }
        }
        .sheet(isPresented: $startWeekOn) {
            RadioDialog(title: nil, items: [7, 1, 2, 3, 4, 5, 6].map { ($0, WeekDays.names[$0 - 1]) }, selected: weekDays.firstDayOfWeek) {
                weekDays.firstDayOfWeek = $0
            }
        }
        .sheet(isPresented: $alarmMaxReminder) {
            PickSecondsDialog(curSeconds: config.alarmMaxReminderSecs, isSnoozePicker: true, showSecondsAtCustomDialog: true) {
                config.alarmMaxReminderSecs = $0 != 0 ? $0 : ClockConstants.defaultMaxAlarmReminderSecs
            }
        }
        .sheet(isPresented: $snoozeTime) {
            PickSecondsDialog(curSeconds: reminders.snoozeTime * 60, isSnoozePicker: true) { reminders.snoozeTime = $0 / 60 }
        }
        .sheet(isPresented: $timerMaxReminder) {
            PickSecondsDialog(curSeconds: config.timerMaxReminderSecs, isSnoozePicker: true, showSecondsAtCustomDialog: true) {
                config.timerMaxReminderSecs = $0 != 0 ? $0 : ClockConstants.defaultMaxTimerReminderSecs
            }
        }
        .sheet(isPresented: $exportName) {
            ExportDataDialog { name in
                guard let data = store.exportData() else { return }
                exportDocument = BackupDocument(data: data)
                exportFilename = name
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exporting = true }
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: exportFilename) { result in
            switch result {
            case .success: store.toast = "Exporting successful"
            case .failure: store.toast = "Exporting failed"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { store.importData(url) }
        }
    }

    private var defaultTabTitle: String {
        ClockTab.allCases.first { $0.bit == config.defaultTab }?.title ?? "Last used one"
    }
}

extension AppInfo {
    public static let clock = AppInfo(
        name: "Clock", icon: "clock.fill", upstream: "Clock", port: "clock-ios", policy: "clock",
        faq: [("How can I change lap sorting at the stopwatch tab?",
               "Just click on any of the columns, that will make the laps be sorted by the given column. With additional clicks you can toggle between ascending and descending sorting.")]
    )
}
