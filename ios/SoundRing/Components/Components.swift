import SwiftUI

// Small pieces reused across the screens.

/// Big cyan button ("Sign in", "Continue to next step", "Finish setup").
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.plain)
    }
}

/// Dark button under a primary one ("Create an account", "Try alignment again").
struct SecondaryButton: View {
    let title: String
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surfaceRaised))
                .foregroundStyle(dimmed ? Theme.secondaryText : Theme.text)
        }
        .buttonStyle(.plain)
    }
}

/// Rounded dark card with a thin border.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 18
    var stroke: Color = Theme.line

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = 18, stroke: Color = Theme.line) -> some View {
        modifier(CardBackground(radius: radius, stroke: stroke))
    }
}

/// The round person button top-right on Home and Pins. Opens the profile.
struct AvatarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "figure.stand")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.accentDim))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }
}

/// Back chevron + "1 Find / 2 Connect / 3 Align" progress bar at the top of the setup screens.
struct StepHeader: View {
    let step: Int            // 1...3
    let onBack: () -> Void
    private let titles = ["Find", "Connect", "Align"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(i < step ? Theme.accent : Theme.secondaryText.opacity(0.6))
                            .frame(height: 4)
                        Text("\(i + 1) \(titles[i])")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(i < step ? Theme.accent : Theme.secondaryText)
                    }
                }
            }
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

/// The receding grid behind the Live dial.
struct PerspectiveGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let vanish = CGPoint(x: size.width / 2, y: size.height * 0.45)
            var lines = Path()
            for i in 0...10 {
                let x = size.width * CGFloat(i) / 10
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: vanish)
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: vanish)
            }
            for i in 1...7 {
                let t = pow(CGFloat(i) / 7, 1.8)
                let dy = (size.height - vanish.y) * t
                lines.move(to: CGPoint(x: 0, y: vanish.y + dy))
                lines.addLine(to: CGPoint(x: size.width, y: vanish.y + dy))
                lines.move(to: CGPoint(x: 0, y: vanish.y - vanish.y * t))
                lines.addLine(to: CGPoint(x: size.width, y: vanish.y - vanish.y * t))
            }
            ctx.stroke(lines, with: .color(Theme.accent.opacity(0.08)), lineWidth: 1)
        }
    }
}
