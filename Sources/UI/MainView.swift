import FossifyCommons
import SwiftUI

/// MainActivity: top app bar with the menu, the four tabs in a pager and the bottom tab bar.
struct MainView: View {
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(ClockStore.self) private var store
    @Environment(\.palette) private var palette

    @State private var tab: ClockTab = .clock
    @State private var didPickTab = false
    @State private var selectedZones = Set<Int>()
    @State private var selectedAlarms = Set<Int>()
    @State private var selectedTimers = Set<Int>()
    @State private var showAlarmSort = false
    @State private var showTimerSort = false

    private var selectionCount: Int {
        switch tab {
        case .clock: return selectedZones.count
        case .alarm: return selectedAlarms.count
        case .timer: return selectedTimers.count
        case .stopwatch: return 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if selectionCount > 0 {
                SelectionBar(count: selectionCount, onClose: clearSelection, onSelectAll: selectAll, onDelete: deleteSelected)
            } else {
                topBar
            }
            TabView(selection: $tab) {
                ClockTabView(selection: $selectedZones).tag(ClockTab.clock)
                AlarmTabView(selection: $selectedAlarms).tag(ClockTab.alarm)
                StopwatchTabView().tag(ClockTab.stopwatch)
                TimerTabView(selection: $selectedTimers).tag(ClockTab.timer)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomTabs
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear(perform: pickDefaultTab)
        .onChange(of: tab) { _, t in
            config.lastUsedViewPagerPage = t.rawValue
            clearSelection()
        }
        .onChange(of: store.requestedTab) { _, t in
            if let t {
                tab = t
                store.requestedTab = nil
            }
        }
        .sheet(isPresented: $showAlarmSort) { ChangeAlarmSortDialog() }
        .sheet(isPresented: $showTimerSort) { ChangeTimerSortDialog() }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            CloseAppButton()
            Text("Clock")
                .font(.system(size: 21, weight: .medium))
                .padding(.leading, 12)
            Spacer()
            if tab == .alarm || tab == .timer {
                IconButton(icon: "arrow.up.arrow.down") {
                    if tab == .alarm { showAlarmSort = true } else { showTimerSort = true }
                }
            }
            Menu {
                Button { router.push(.settings) } label: { Label("Settings", systemImage: "gearshape") }
                Button { router.push(.about) } label: { Label("About", systemImage: "info.circle") }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 18))
                    .frame(width: 44, height: 48)
            }
        }
        .foregroundStyle(palette.textColor)
        .padding(.horizontal, 4)
        .frame(height: 56)
    }

    private var bottomTabs: some View {
        HStack(spacing: 0) {
            ForEach(ClockTab.allCases) { t in
                Button {
                    withAnimation { tab = t }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon(selected: t == tab)).font(.system(size: 20))
                        Text(t.title).font(.system(size: 13, weight: t == tab ? .semibold : .regular)).lineLimit(1)
                    }
                    .foregroundStyle(t == tab ? palette.primaryColor : palette.textColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.surface.ignoresSafeArea(edges: .bottom))
    }

    private func pickDefaultTab() {
        guard !didPickTab else { return }
        didPickTab = true
        if let requested = store.requestedTab {
            tab = requested
            store.requestedTab = nil
            return
        }
        tab = ClockTab.allCases.first { $0.bit == config.defaultTab }
            ?? ClockTab(rawValue: config.lastUsedViewPagerPage) ?? .clock
    }

    private func clearSelection() {
        selectedZones.removeAll()
        selectedAlarms.removeAll()
        selectedTimers.removeAll()
    }

    private func selectAll() {
        switch tab {
        case .clock: selectedZones = Set(config.selectedTimeZones.compactMap { Int($0) })
        case .alarm: selectedAlarms = Set(store.alarms.map(\.id))
        case .timer: selectedTimers = Set(store.timers.compactMap(\.id))
        case .stopwatch: break
        }
    }

    private func deleteSelected() {
        switch tab {
        case .clock:
            let ids = selectedZones.map { "\($0)" }
            config.selectedTimeZones = config.selectedTimeZones.filter { !ids.contains($0) }
        case .alarm: store.deleteAlarms(selectedAlarms)
        case .timer: store.deleteTimers(selectedTimers)
        case .stopwatch: break
        }
        clearSelection()
    }
}
