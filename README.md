# clock-ios

[Fossify Clock](https://github.com/FossifyOrg/Clock) re-created for iOS in SwiftUI, ringing through AlarmKit (iOS 26+) or local notifications.

    idl build -c release     # -> build/release/FossifyClock.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyClock

Ported: the clock tab with extra time zones (add, rename, delete) and the next alarm; alarms with weekdays, sound (default, none or your own audio files), vibration, label, snooze, the "upcoming alarm" notice that skips the next ring, sorting and drag reordering, and the swipe-to-dismiss/snooze alarm screen; the stopwatch with sortable laps; any number of timers with sound, vibration, label, sorting and reordering; export/import of alarms and timers (same JSON as Android); colors and every applicable setting.

Differences forced by iOS: no home-screen widgets (they would need a WidgetKit extension plus an App Group), no "Start stopwatch" launcher shortcut and no ongoing "running" notification for timers and the stopwatch; with AlarmKit the system alert rings (snooze uses the snooze time; vibration, gradual volume and the max reminder duration only apply while the app is open); without it alarms are time-sensitive notifications that play up to 30 seconds of sound; system ringtones can't be listed; no in-app language switch.

GPL-3.0, like the original.
