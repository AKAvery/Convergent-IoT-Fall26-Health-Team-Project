import SwiftUI

// Small pieces reused across the screens.

/// Full-width filled button. Used once per screen at most, for the step that moves the user
/// forward ("Sign in", "Continue to next step", "Finish setup", "Start live view").
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(FilledButtonStyle())
    }
}

/// Full-width quiet button under a primary one ("Create an account").
struct SecondaryButton: View {
    let title: String
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(FilledButtonStyle(fill: Theme.fill, foreground: dimmed ? Theme.secondaryText : Theme.text))
    }
}

struct FilledButtonStyle: ButtonStyle {
    var fill: Color = Theme.accent
    var foreground: Color = Theme.onAccent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.vertical, 14)
            .padding(.horizontal, Theme.Space.l)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

/// Opens the profile. Lives in the navigation bar on Home and Pins.
struct AvatarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
        }
        .accessibilityLabel("Profile")
    }
}

/// Back button and "1 Find / 2 Connect / 3 Align" progress at the top of the setup screens.
struct StepHeader: View {
    let step: Int            // 1...3
    let onBack: () -> Void
    private let titles = ["Find", "Connect", "Align"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Button(action: onBack) {
                if step == 1 {
                    Text("Cancel")
                } else {
                    Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.borderless)
            .tint(Theme.accent)
            HStack(spacing: Theme.Space.xs) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Capsule()
                            .fill(i < step ? Theme.accent : Theme.fill)
                            .frame(height: 3)
                        Text("\(i + 1) \(titles[i])")
                            .font(.caption.weight(i + 1 == step ? .semibold : .regular))
                            .foregroundStyle(i + 1 == step ? Theme.text : Theme.secondaryText)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step) of 3, \(titles[step - 1])")
        }
    }
}

/// The Bluetooth rune (SF Symbols has none).
struct BluetoothGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.2, 0.3))
        path.addLine(to: p(0.8, 0.72))
        path.addLine(to: p(0.5, 0.95))
        path.addLine(to: p(0.5, 0.05))
        path.addLine(to: p(0.8, 0.28))
        path.addLine(to: p(0.2, 0.7))
        return path
    }
}

/// Bars under the main sound on Live. Holds still when Reduce Motion is on.
struct Waveform: View {
    let color: Color
    var bars = 40
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let step = size.width / CGFloat(bars)
                for i in 0..<bars {
                    let x = CGFloat(i) * step + step / 2
                    let center = 1 - abs(Double(i) / Double(bars - 1) - 0.5) * 1.4
                    let wobble = 0.5 + 0.5 * sin(t * 6 + Double(i) * 0.9) * cos(t * 2.3 + Double(i) * 0.37)
                    let h = max(2, size.height * CGFloat(max(0.08, center * wobble)))
                    let bar = Path(roundedRect: CGRect(x: x - 1, y: (size.height - h) / 2, width: 2, height: h),
                                   cornerRadius: 1)
                    ctx.fill(bar, with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A plain section label for screens that aren't a List: "Sounds today".
struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rounded panel with a hairline border. Kept only until the screens move to native lists.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.Radius.control
    var stroke: Color = Theme.line

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = Theme.Radius.control, stroke: Color = Theme.line) -> some View {
        modifier(CardBackground(radius: radius, stroke: stroke))
    }
}
