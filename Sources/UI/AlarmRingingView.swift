import FossifyCommons
import SwiftUI
import UIKit

/// AlarmActivity: label, current time and the draggable alarm icon (right to dismiss,
/// left to snooze).
struct AlarmRingingView: View {
    @Environment(ClockStore.self) private var store
    @Environment(\.palette) private var palette
    let alarm: Alarm
    @State private var offset: CGFloat = 0
    @State private var done = false
    @State private var showGuide = false
    @State private var pulse = false
    @State private var pickSnooze = false

    private let threshold: CGFloat = 50

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                .font(.system(size: 32))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(ClockTime.formattedString(passedSeconds: ClockTime.passedSeconds(context.date), showSeconds: false))
                    .font(.system(size: 26))
                    .padding(.top, 8)
            }
            Spacer()
            GeometryReader { geo in
                let maxDrag = geo.size.width / 2 - 50
                ZStack {
                    HStack {
                        control("zzz", "Snooze")
                        Spacer()
                        control("alarm.waves.left.and.right", "Dismiss")
                    }
                    Circle()
                        .fill(palette.primaryColor.opacity(0.2))
                        .frame(width: 70, height: 70)
                        .scaleEffect(pulse ? 1.6 : 1)
                        .opacity(offset == 0 ? 1 : 0)
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 30))
                        .frame(width: 70, height: 70)
                        .contentShape(Circle())
                        .offset(x: offset)
                        .gesture(DragGesture()
                            .onChanged { value in
                                guard !done else { return }
                                offset = min(maxDrag, max(-maxDrag, value.translation.width))
                                if offset >= maxDrag - threshold { finish(dismiss: true) } else if offset <= -maxDrag + threshold { finish(dismiss: false) }
                            }
                            .onEnded { _ in
                                guard !done else { return }
                                withAnimation { offset = 0 }
                                withAnimation { showGuide = true }
                            })
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 120)
            .padding(.horizontal, 24)
            Text("Swipe right to Dismiss, or left to Snooze.")
                .font(.system(size: 15))
                .opacity(showGuide ? 1 : 0)
                .padding(.vertical, 24)
                .task(id: showGuide) {
                    guard showGuide else { return }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { showGuide = false }
                }
        }
        .foregroundStyle(palette.textColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .sheet(isPresented: $pickSnooze) {
            PickSecondsDialog(curSeconds: ReminderConfig.shared.snoozeTime * 60, isSnoozePicker: true,
                              onCancel: { store.stopAlarm(alarm.id) }) { seconds in
                ReminderConfig.shared.snoozeTime = seconds / 60
                store.snoozeAlarm(alarm.id, minutes: ReminderConfig.shared.snoozeTime)
            }
        }
    }

    private func control(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 26))
            Text(title).font(.system(size: 14))
        }
        .frame(width: 80)
    }

    private func finish(dismiss: Bool) {
        done = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        if dismiss {
            store.stopAlarm(alarm.id)
        } else if ReminderConfig.shared.useSameSnooze {
            store.snoozeAlarm(alarm.id, minutes: ReminderConfig.shared.snoozeTime)
        } else {
            store.silenceAlarm(alarm.id)
            pickSnooze = true
        }
    }
}
