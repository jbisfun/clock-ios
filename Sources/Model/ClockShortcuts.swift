import Foundation

/// OPEN_TAB for hosts (the launcher's alarm/timer quick settings tiles and notification taps):
/// the tab ClockRoot shows when it appears or is already shown.
@MainActor
public enum ClockShortcuts {
    public enum Tab { case clock, alarm, stopwatch, timer }

    public static func request(_ tab: Tab) {
        let t: ClockTab
        switch tab {
        case .clock: t = .clock
        case .alarm: t = .alarm
        case .stopwatch: t = .stopwatch
        case .timer: t = .timer
        }
        ClockStore.shared.requestedTab = t
    }
}
