import FossifyCommons
import SwiftUI

/// TimerFragment + TimerAdapter.
struct TimerTabView: View {
    @Environment(ClockStore.self) private var store
    @Environment(\.palette) private var palette
    @Binding var selection: Set<Int>
    @State private var editing: ClockTimer?
    @State private var needPermission = false

    var body: some View {
        let timers = store.sortedTimers
        ZStack(alignment: .bottomTrailing) {
            if timers.isEmpty {
                Placeholder(text: "No timers found")
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(timers) { timer in
                            TimerRow(timer: timer, onReset: { reset(timer) }, onToggle: { toggle(timer) })
                                .selectable(selected: selection.contains(timer.id ?? -1), selecting: !selection.isEmpty,
                                            onTap: { editing = timer }, onToggle: { if let id = timer.id { selection.toggle(id) } })
                                .id(timer.id)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(palette.backgroundColor)
                        }
                        .onMove { from, to in
                            var list = timers
                            list.move(fromOffsets: from, toOffset: to)
                            store.saveTimersCustomOrder(list)
                        }
                        Color.clear.frame(height: 80).listRowBackground(palette.backgroundColor).listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(selection.isEmpty ? .inactive : .active))
                    .onAppear { scroll(proxy) }
                    .onChange(of: store.requestedTimerID) { _, _ in scroll(proxy) }
                }
            }
            if selection.isEmpty {
                Fab { editing = store.createNewTimer() }
            }
        }
        .sheet(item: Binding(get: { editing.map(EditedTimer.init) }, set: { editing = $0?.timer })) { item in
            EditTimerDialog(timer: item.timer)
        }
        .alert("You must allow the app displaying notifications, else it cannot show reminders.", isPresented: $needPermission) {
            Button("Cancel", role: .cancel) {}
            Button("OK") { SystemSettings.open() }
        }
    }

    /// TimerFragment.updatePosition().
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = store.requestedTimerID else { return }
        store.requestedTimerID = nil
        withAnimation { proxy.scrollTo(Optional(id), anchor: .center) }
    }

    /// TimerAdapter.toggleTimer() behind handleNotificationPermission().
    private func toggle(_ timer: ClockTimer) {
        guard let id = timer.id else { return }
        Task {
            if await AlarmScheduler.requestAlarmPermission() {
                store.toggleTimer(id)
            } else {
                needPermission = true
            }
        }
    }

    private func reset(_ timer: ClockTimer) {
        if let id = timer.id { store.resetTimer(id) }
    }
}

/// A sheet item for a timer that may not have an id yet.
struct EditedTimer: Identifiable {
    let timer: ClockTimer
    var id: Int { timer.id ?? -1 }
}

/// item_timer.
struct TimerRow: View {
    @Environment(\.palette) private var palette
    let timer: ClockTimer
    let onReset: () -> Void
    let onToggle: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(timeText)
                        .font(.system(size: 48, weight: .light))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if !timer.label.isEmpty {
                        Text(timer.label).font(.system(size: 16)).lineLimit(1)
                    }
                }
                Spacer()
                let resettable = timer.state != .idle
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 20)).frame(width: 50, height: 50)
                }
                .opacity(resettable ? 1 : 0)
                .disabled(!resettable)
                Button(action: onToggle) {
                    Image(systemName: timer.state.isRunning ? "pause.fill" : "play.fill").font(.system(size: 22)).frame(width: 56, height: 56)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var timeText: String {
        switch timer.state {
        case .finished: return 0.formattedDuration()
        case .idle: return timer.seconds.formattedDuration()
        case .paused, .running: return ClockTime.duration(ms: timer.state.tick)
        }
    }
}
