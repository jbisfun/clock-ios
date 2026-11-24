import AudioToolbox
import FossifyCommons
import Foundation

/// AlarmService's sound and vibration while an alarm or a finished timer rings in the app:
/// loops the sound, optionally raises the volume gradually and vibrates, and calls
/// `onTimeout` after the max reminder duration.
@MainActor
final class Ringer {
    private let player = AlarmSoundPlayer()
    private var vibrateTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func start(sound: AlarmSound, vibrate: Bool, increaseVolume: Bool, maxSeconds: Int, onTimeout: @escaping () -> Void) {
        stop()
        player.play(sound, loop: true, volume: increaseVolume ? 0.1 : 1)
        if increaseVolume {
            // scheduleVolumeIncrease(): small steps every 300 ms.
            volumeTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self, self.player.volume < 1 else { return }
                    self.player.volume = min(1, self.player.volume + 0.01)
                }
            }
        }
        if vibrate {
            vibrateTask = Task {
                while !Task.isCancelled {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(maxSeconds))
            if !Task.isCancelled { onTimeout() }
        }
    }

    func stop() {
        player.stop()
        vibrateTask?.cancel()
        volumeTask?.cancel()
        timeoutTask?.cancel()
        vibrateTask = nil
        volumeTask = nil
        timeoutTask = nil
    }
}
