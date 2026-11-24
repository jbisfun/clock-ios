import FossifyCommons
import SwiftUI

/// ClockFragment: the current time and date, the next alarm and the chosen time zones.
struct ClockTabView: View {
    @Environment(Config.self) private var config
    @Environment(ClockStore.self) private var store
    @Environment(\.palette) private var palette
    @Binding var selection: Set<Int>
    @State private var addZones = false
    @State private var editZone: MyTimeZone?

    var body: some View {
        let selectedIDs = Set(config.selectedTimeZones.compactMap { Int($0) })
        let zones = config.allTimeZonesModified.filter { selectedIDs.contains($0.id) }
        ZStack(alignment: .bottomTrailing) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let today = ClockTime.formattedDate(context.date)
                ScrollView {
                    VStack(spacing: 0) {
                        TimeText(passedSeconds: ClockTime.passedSeconds(context.date), showSeconds: true, size: 80)
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        Text(today)
                            .font(.system(size: 18))
                            .padding(.top, 4)
                        let nextAlarm = store.closestEnabledAlarmString
                        if !nextAlarm.isEmpty {
                            Label(nextAlarm, systemImage: "alarm")
                                .font(.system(size: 18))
                                .padding(.top, 8)
                        }
                        LazyVStack(spacing: 0) {
                            ForEach(zones) { zone in
                                TimeZoneRow(zone: zone, date: context.date, today: today)
                                    .selectable(selected: selection.contains(zone.id), selecting: !selection.isEmpty,
                                                onTap: { editZone = zone }, onToggle: { selection.toggle(zone.id) })
                            }
                        }
                        .padding(.top, 24)
                    }
                    .padding(.bottom, 90)
                }
            }
            if selection.isEmpty {
                Fab { addZones = true }
            }
        }
        .sheet(isPresented: $addZones) { AddTimeZonesDialog() }
        .sheet(item: $editZone) { EditTimeZoneDialog(zone: $0) }
    }
}

/// item_time_zone.
struct TimeZoneRow: View {
    let zone: MyTimeZone
    let date: Date
    let today: String

    var body: some View {
        let tz = TimeZone(identifier: zone.zoneName) ?? .current
        let formattedDate = ClockTime.formattedDate(date, in: tz)
        HStack(alignment: .center) {
            Text(zone.title)
                .font(.system(size: 18))
                .lineLimit(2)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ClockTime.formattedString(passedSeconds: ClockTime.passedSeconds(date, in: tz), showSeconds: false))
                    .font(.system(size: 20))
                    .monospacedDigit()
                if formattedDate != today {
                    Text(formattedDate).font(.system(size: 14))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
