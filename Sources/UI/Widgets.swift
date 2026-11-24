import FossifyCommons
import SwiftUI

/// The clock's home-screen widgets for launcher-ios: MyDigitalTimeWidgetProvider and
/// MyAnalogueTimeWidgetProvider with their configure activities.
public enum ClockWidgets {
    public static let all: [HomeWidgetKind] = [digital, analogue]

    /// widget_digital_clock_info: 3x1 cells, resizable down to one cell wide.
    static let digital = HomeWidgetKind(
        id: "clock.digital", title: "Digital clock",
        defaultSize: CGSize(width: 3, height: 1), minSize: CGSize(width: 1, height: 1), resizable: true,
        configure: { context, done in AnyView(WidgetConfigView(context: context, digital: true, done: done)) },
        content: { context in AnyView(DigitalClockWidget(context: context)) })

    /// widget_analogue_clock_info: 2x1 cells, resizable down to one cell wide.
    static let analogue = HomeWidgetKind(
        id: "clock.analogue", title: "Analogue clock",
        defaultSize: CGSize(width: 2, height: 1), minSize: CGSize(width: 1, height: 1), resizable: true,
        configure: { context, done in AnyView(WidgetConfigView(context: context, digital: false, done: done)) },
        content: { context in AnyView(AnalogueClockWidget(context: context)) })
}

/// Widget colors (BaseConfig.widgetBgColor / widgetTextColor), kept per placed widget.
enum ClockWidgetColors {
    /// default_widget_bg_color
    static let defaultBackground: UInt32 = 0xAA000000
    /// default_widget_text_color = color_primary (md_green_900)
    static let defaultText: UInt32 = 0xFF106D1F

    static func background(_ context: HomeWidgetContext) -> AppStorage<Int> {
        AppStorage(wrappedValue: Int(defaultBackground), context.key("bg_color"))
    }

    static func text(_ context: HomeWidgetContext) -> AppStorage<Int> {
        AppStorage(wrappedValue: Int(defaultText), context.key("text_color"))
    }
}

/// widget_round_background tinted with the widget background color.
private struct WidgetBackground: View {
    let color: UInt32

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(argb: color))
    }
}

private extension View {
    /// shadowColor black, shadowDy 1, shadowRadius 1.
    func widgetShadow() -> some View { shadow(color: .black, radius: 1, x: 0, y: 1) }
}

// MARK: Digital (widget_digital)

struct DigitalClockWidget: View {
    let context: HomeWidgetContext
    @AppStorage private var bgColor: Int
    @AppStorage private var textColor: Int

    init(context: HomeWidgetContext) {
        self.context = context
        _bgColor = ClockWidgetColors.background(context)
        _textColor = ClockWidgetColors.text(context)
    }

    var body: some View {
        ZStack {
            WidgetBackground(color: UInt32(truncatingIfNeeded: bgColor))
            DigitalClockFace(textColor: UInt32(truncatingIfNeeded: textColor), showAlarm: true)
                .padding([.horizontal, .bottom], 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { context.openApp(nil) }
    }
}

/// The time (HH:mm or h:mm a per the 24-hour setting), "EEE, d MMM" and the next alarm,
/// stacked with weights 4:1:1 and auto-sized like the TextClocks.
struct DigitalClockFace: View {
    let textColor: UInt32
    let showAlarm: Bool

    var body: some View {
        let format = DateTimeFormat.shared
        let nextAlarm = showAlarm ? ClockStore.shared.closestEnabledAlarmString : ""
        let color = Color(argb: textColor)
        TimelineView(.everyMinute) { timeline in
            GeometryReader { geo in
                let weights: CGFloat = nextAlarm.isEmpty ? 5 : 6
                let unit = geo.size.height / weights
                VStack(spacing: 0) {
                    autoSized(DateTimeFormat.format(timeline.date, format.use24HourFormat ? "HH:mm" : "h:mm a"),
                              height: unit * 4)
                    autoSized(Self.dateString(timeline.date), height: unit)
                    if !nextAlarm.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "alarm")
                                .resizable()
                                .scaledToFit()
                                .frame(width: min(18, unit), height: min(18, unit))
                            Text(nextAlarm)
                                .font(.system(size: min(14, unit * 0.9)))
                                .lineLimit(1)
                                .minimumScaleFactor(0.2)
                        }
                        .frame(height: unit)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .foregroundStyle(color)
        .widgetShadow()
    }

    private func autoSized(_ text: String, height: CGFloat) -> some View {
        Text(text)
            .font(.system(size: max(2, height * 0.95)))
            .lineLimit(1)
            .minimumScaleFactor(0.02)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    /// TextClock format "EEE, d MMM".
    static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEE, d MMM"
        return f.string(from: date)
    }
}

// MARK: Analogue (widget_analogue)

struct AnalogueClockWidget: View {
    let context: HomeWidgetContext
    @AppStorage private var bgColor: Int

    init(context: HomeWidgetContext) {
        self.context = context
        _bgColor = ClockWidgetColors.background(context)
    }

    var body: some View {
        ZStack {
            WidgetBackground(color: UInt32(truncatingIfNeeded: bgColor))
            AnalogueClockFace()
                .padding([.horizontal, .bottom], 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { context.openApp(nil) }
    }
}

/// Android's AnalogClock: twelve tick marks and white hour/minute hands, square and centered.
struct AnalogueClockFace: View {
    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let c = Calendar.current.dateComponents([.hour, .minute, .second], from: timeline.date)
            let minutes = Double(c.minute ?? 0) + Double(c.second ?? 0) / 60
            let hours = Double((c.hour ?? 0) % 12) + minutes / 60
            Canvas { ctx, size in
                let side = min(size.width, size.height)
                let r = side / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                func point(_ angle: Double, _ length: CGFloat) -> CGPoint {
                    let a = angle * .pi / 180
                    return CGPoint(x: center.x + CGFloat(sin(a)) * length, y: center.y - CGFloat(cos(a)) * length)
                }
                ctx.addFilter(.shadow(color: .black.opacity(0.6), radius: max(1, r * 0.03), x: 0, y: max(0.5, r * 0.01)))
                for i in 0..<12 {
                    var tick = Path()
                    tick.move(to: point(Double(i) * 30, r * 0.78))
                    tick.addLine(to: point(Double(i) * 30, r * 0.92))
                    ctx.stroke(tick, with: .color(.white), style: StrokeStyle(lineWidth: max(1, r * 0.045), lineCap: .round))
                }
                var hour = Path()
                hour.move(to: center)
                hour.addLine(to: point(hours * 30, r * 0.5))
                ctx.stroke(hour, with: .color(.white), style: StrokeStyle(lineWidth: max(1.5, r * 0.08), lineCap: .round))
                var minute = Path()
                minute.move(to: center)
                minute.addLine(to: point(minutes * 6, r * 0.72))
                ctx.stroke(minute, with: .color(.white), style: StrokeStyle(lineWidth: max(1, r * 0.05), lineCap: .round))
            }
        }
    }
}

// MARK: Configure (WidgetDigitalConfigureActivity / WidgetAnalogueConfigureActivity)

struct WidgetConfigView: View {
    let context: HomeWidgetContext
    let digital: Bool
    let done: (Bool) -> Void

    var body: some View {
        WidgetConfigContent(context: context, digital: digital, done: done).fossifyTheme()
    }
}

private struct WidgetConfigContent: View {
    @Environment(\.palette) private var palette
    let context: HomeWidgetContext
    let digital: Bool
    let done: (Bool) -> Void

    @State private var bgColorWithoutTransparency: UInt32
    @State private var bgAlpha: Double
    @State private var textColor: UInt32
    @State private var picking: Picking?

    private enum Picking: Int, Identifiable {
        case background, text
        var id: Int { rawValue }
    }

    init(context: HomeWidgetContext, digital: Bool, done: @escaping (Bool) -> Void) {
        self.context = context
        self.digital = digital
        self.done = done
        let d = UserDefaults.standard
        let bg = (d.object(forKey: context.key("bg_color")) as? Int).map { UInt32(truncatingIfNeeded: $0) } ?? ClockWidgetColors.defaultBackground
        _bgColorWithoutTransparency = State(initialValue: bg | 0xFF000000)
        _bgAlpha = State(initialValue: Double(bg >> 24) / 255)
        let text = (d.object(forKey: context.key("text_color")) as? Int).map { UInt32(truncatingIfNeeded: $0) } ?? ClockWidgetColors.defaultText
        _textColor = State(initialValue: text)
    }

    /// adjustAlpha(mBgAlpha)
    private var bgColor: UInt32 {
        UInt32((bgAlpha * 255).rounded()) << 24 | (bgColorWithoutTransparency & 0xFFFFFF)
    }

    var body: some View {
        VStack(spacing: 16) {
            TopBar(title: digital ? "Digital clock" : "Analogue clock", onBack: { done(false) })
            Spacer(minLength: 0)
            preview
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    swatch(bgColor) { picking = .background }
                    Slider(value: $bgAlpha, in: 0...1)
                        .tint(palette.primaryColor)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(Capsule().fill(palette.textColor.opacity(0.1)))
                }
                HStack(spacing: 12) {
                    if digital {
                        swatch(textColor) { picking = .text }
                    }
                    Spacer()
                    Button { save() } label: {
                        Text("OK")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.onPrimary)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(palette.primaryColor))
                    }
                }
            }
            .padding(16)
        }
        .paletteBackground()
        .sheet(item: $picking) { which in
            switch which {
            case .background:
                ColorPickerDialog(title: "Background color", color: bgColorWithoutTransparency) { bgColorWithoutTransparency = $0 }
            case .text:
                ColorPickerDialog(title: "Text color", color: textColor) { textColor = $0 }
            }
        }
    }

    private var preview: some View {
        ZStack {
            WidgetBackground(color: bgColor)
            if digital {
                DigitalClockFace(textColor: textColor, showAlarm: false)
                    .padding([.horizontal, .bottom], 4)
            } else {
                AnalogueClockFace().padding([.horizontal, .bottom], 4)
            }
        }
        .frame(height: digital ? 120 : 160)
        .frame(maxWidth: digital ? .infinity : 160)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.35)))
    }

    /// setFillWithStroke() color circle.
    private func swatch(_ color: UInt32, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(argb: color))
                .overlay(Circle().stroke(palette.textColor.opacity(0.4), lineWidth: 1))
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
    }

    /// saveConfig(): storeWidgetColors() and report RESULT_OK.
    private func save() {
        let d = UserDefaults.standard
        d.set(Int(bgColor), forKey: context.key("bg_color"))
        if digital { d.set(Int(textColor), forKey: context.key("text_color")) }
        done(true)
    }
}
