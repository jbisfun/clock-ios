import Foundation
import Observation

/// helpers/Stopwatch.kt: an in-memory stopwatch with laps. Times are measured with
/// the monotonic uptime clock, so they keep running while the app is in the background.
@MainActor
@Observable
final class Stopwatch {
    static let shared = Stopwatch()

    enum State { case running, paused, stopped }

    private(set) var state = State.stopped
    private(set) var laps: [Lap] = []
    /// Updated every 100 ms while running (UPDATE_INTERVAL_MS).
    private(set) var totalTime: Int64 = 0
    private(set) var lapTime: Int64 = 0

    @ObservationIgnored private var startTime: Int64 = 0
    @ObservationIgnored private var accumulatedTime: Int64 = 0
    @ObservationIgnored private var lapStartTime: Int64 = 0
    @ObservationIgnored private var accumulatedLapTime: Int64 = 0
    @ObservationIgnored private var currentLap = 1
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    private init() {}

    /// useLongerMSFormat: milliseconds are shown with three digits when not running.
    var useLongerMSFormat: Bool { state == .paused }

    /// SystemClock.elapsedRealtime(): monotonic, including time asleep.
    private static func now() -> Int64 { Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000) }

    func reset() {
        updateTask?.cancel()
        state = .stopped
        accumulatedTime = 0
        lapStartTime = 0
        accumulatedLapTime = 0
        currentLap = 1
        laps.removeAll()
        totalTime = 0
        lapTime = 0
    }

    func toggle() {
        let now = Self.now()
        if state != .running {
            state = .running
            startTime = now
            lapStartTime = now
            startUpdates()
        } else {
            state = .paused
            updateTask?.cancel()
            accumulatedTime += now - startTime
            accumulatedLapTime += now - lapStartTime
            totalTime = accumulatedTime
            lapTime = accumulatedLapTime
        }
    }

    func lap() {
        guard state == .running else { return }
        let now = Self.now()
        let lap = Lap(id: currentLap, lapTime: accumulatedLapTime + (now - lapStartTime), totalTime: accumulatedTime + (now - startTime))
        currentLap += 1
        laps.insert(lap, at: 0)
        lapStartTime = now
        accumulatedLapTime = 0
    }

    private func startUpdates() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.state == .running else { return }
                let now = Self.now()
                self.totalTime = self.accumulatedTime + (now - self.startTime)
                self.lapTime = self.accumulatedLapTime + (now - self.lapStartTime)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
