import FossifyCommons
import SwiftUI

/// StopwatchFragment + StopwatchAdapter.
struct StopwatchTabView: View {
    @Environment(Config.self) private var config
    @Environment(Stopwatch.self) private var stopwatch
    @Environment(\.palette) private var palette

    var body: some View {
        let sorting = config.stopwatchLapsSort
        let showLaps = !stopwatch.laps.isEmpty
        VStack(spacing: 0) {
            Text(ClockTime.stopwatch(stopwatch.totalTime, longerMS: stopwatch.useLongerMSFormat))
                .font(.system(size: 80, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
                .contentShape(Rectangle())
                .onTapGesture { stopwatch.toggle() }
            if showLaps {
                HStack(spacing: 0) {
                    indicator(ClockConstants.sortByLap, sorting)
                    indicator(ClockConstants.sortByLapTime, sorting)
                    indicator(ClockConstants.sortByTotalTime, sorting)
                }
                .padding(.horizontal, 16)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(laps(sorting)) { lap in
                                LapRow(lap: lap, count: stopwatch.laps.count + 1, onSort: changeSorting)
                                    .id(lap.id)
                            }
                        }
                    }
                    .onChange(of: stopwatch.laps.count) { _, _ in scrollToTop(proxy, sorting) }
                    .onChange(of: sorting) { _, _ in scrollToTop(proxy, sorting) }
                }
            } else {
                Spacer()
            }
            controls.padding(.vertical, 16)
        }
        .onAppear {
            if config.toggleStopwatch {
                config.toggleStopwatch = false
                if stopwatch.state == .stopped { stopwatch.toggle() }
            }
        }
    }

    /// Laps plus the live lap while the stopwatch runs, sorted (Lap.compareTo).
    private func laps(_ sorting: Int) -> [Lap] {
        var list = stopwatch.laps
        if !list.isEmpty && stopwatch.state != .stopped {
            list.append(Lap(id: ClockConstants.stopwatchLiveLapID, lapTime: stopwatch.lapTime, totalTime: stopwatch.totalTime))
        }
        return Lap.sorted(list, by: sorting)
    }

    private func scrollToTop(_ proxy: ScrollViewProxy, _ sorting: Int) {
        if let first = laps(sorting).first { proxy.scrollTo(first.id, anchor: .top) }
    }

    private func indicator(_ column: Int, _ sorting: Int) -> some View {
        Image(systemName: sorting & ClockConstants.sortDescending != 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
            .font(.system(size: 10))
            .foregroundStyle(palette.primaryColor)
            .opacity(sorting & column != 0 ? 1 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle())
            .onTapGesture { changeSorting(column) }
    }

    /// StopwatchFragment.changeSorting().
    private func changeSorting(_ clicked: Int) {
        let sorting = config.stopwatchLapsSort
        config.stopwatchLapsSort = sorting & clicked != 0 ? sorting ^ ClockConstants.sortDescending : clicked | ClockConstants.sortDescending
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button { stopwatch.reset() } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 24)).frame(width: 60, height: 60)
            }
            .opacity(stopwatch.state != .stopped ? 1 : 0)
            .disabled(stopwatch.state == .stopped)
            Button { stopwatch.toggle() } label: {
                Image(systemName: stopwatch.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(palette.primary.isWhite ? .black : .white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(palette.primaryColor))
            }
            Button { stopwatch.lap() } label: {
                Image(systemName: "stopwatch").font(.system(size: 24)).frame(width: 60, height: 60)
            }
            .opacity(stopwatch.state == .running ? 1 : 0)
            .disabled(stopwatch.state != .running)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.textColor)
    }
}

/// item_lap: number, lap time and total time; tapping a column sorts by it.
struct LapRow: View {
    let lap: Lap
    let count: Int
    let onSort: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            cell(lap.isLive ? "\(count)" : "\(lap.id)", ClockConstants.sortByLap)
            cell(ClockTime.stopwatch(lap.lapTime, longerMS: false), ClockConstants.sortByLapTime)
            cell(ClockTime.stopwatch(lap.totalTime, longerMS: false), ClockConstants.sortByTotalTime)
        }
        .padding(.horizontal, 16)
    }

    private func cell(_ text: String, _ column: Int) -> some View {
        Text(text)
            .font(.system(size: 16))
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { onSort(column) }
    }
}
