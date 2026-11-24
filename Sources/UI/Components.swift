import FossifyCommons
import SwiftUI
import UIKit

/// MyFloatingActionButton.
struct Fab: View {
    @Environment(\.palette) private var palette
    var icon = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(palette.onPrimary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(palette.primaryColor))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .padding(16)
    }
}

/// Italic "No alarms found" style placeholder.
struct Placeholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17).italic())
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// getFormattedTime() rendered with the AM/PM part scaled (RelativeSizeSpan / AM_PM_SCALE).
struct TimeText: View {
    let passedSeconds: Int
    var showSeconds = false
    let size: CGFloat
    var amPmScale: CGFloat = 0.4

    var body: some View {
        let (time, ampm) = ClockTime.formatted(passedSeconds: passedSeconds, showSeconds: showSeconds)
        (Text(time).font(.system(size: size, weight: .light))
            + Text(ampm ?? "").font(.system(size: size * amPmScale, weight: .light)))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.3)
    }
}

/// Action mode bar (cab_alarms / cab_timezones): count, select all, delete.
struct SelectionBar: View {
    @Environment(\.palette) private var palette
    let count: Int
    let onClose: () -> Void
    let onSelectAll: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            IconButton(icon: "xmark", action: onClose)
            Text("\(count)").font(.system(size: 20, weight: .medium)).padding(.leading, 8)
            Spacer()
            IconButton(icon: "checklist", action: onSelectAll)
            IconButton(icon: "trash", action: onDelete)
        }
        .foregroundStyle(palette.onPrimary)
        .padding(.horizontal, 4)
        .frame(height: 56)
        .background(palette.primaryColor.ignoresSafeArea(edges: .top))
    }
}

/// A row in a selectable list: tap / long press like MyRecyclerViewAdapter.
struct SelectableRow: ViewModifier {
    @Environment(\.palette) private var palette
    let selected: Bool
    let selecting: Bool
    let onTap: () -> Void
    let onToggle: () -> Void

    func body(content: Content) -> some View {
        content
            .background(selected ? palette.primaryColor.opacity(0.25) : .clear)
            .contentShape(Rectangle())
            .onTapGesture { if selecting { toggle() } else { onTap() } }
            .onLongPressGesture { toggle() }
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onToggle()
    }
}

extension View {
    func selectable(selected: Bool, selecting: Bool, onTap: @escaping () -> Void, onToggle: @escaping () -> Void) -> some View {
        modifier(SelectableRow(selected: selected, selecting: selecting, onTap: onTap, onToggle: onToggle))
    }
}

extension Set {
    mutating func toggle(_ element: Element) {
        if contains(element) { remove(element) } else { insert(element) }
    }
}

/// Opens the app's page in the system settings (openNotificationSettings).
enum SystemSettings {
    static func open() { Launcher.open(URL(string: UIApplication.openSettingsURLString)) }
}
