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

/// Scrolls only when the content is taller than the screen (large text sizes). Otherwise the
/// content fills the screen, so a Spacer can push buttons to the bottom.
struct FillingScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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
