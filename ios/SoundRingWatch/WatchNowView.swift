import SwiftUI

/// Page 1: a top-down view of the wearer with one arrow per sound, and the top sound's name
/// underneath. Nothing else: no chips, distances, filters or waveform (those live on the iPhone).
struct WatchNowView: View {
    let feed: WatchFeed

    var body: some View {
        VStack(spacing: 4) {
            WatchDial(cues: feed.cues, primaryID: feed.primary?.id)
            PrimaryLabel(cue: feed.primary)
        }
        .padding(.horizontal, 4)
    }
}

/// The ring, the wearer in the middle, an arrow on the ring toward each sound. 0° is straight ahead
/// (top of the screen). The top sound gets a big glowing arrow; the rest are small and dim.
struct WatchDial: View {
    let cues: [SoundCue]
    let primaryID: String?

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let ring = s * 0.40
            ZStack {
                Circle()
                    .stroke(Theme.line, lineWidth: 1.5)
                    .frame(width: ring * 2, height: ring * 2)
                    .position(c)
                // Notch at the top = "in front of you".
                Capsule()
                    .fill(Theme.secondaryText)
                    .frame(width: 2, height: s * 0.06)
                    .position(x: c.x, y: c.y - ring)

                Image(systemName: "figure.stand")
                    .font(.system(size: s * 0.13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: s * 0.26, height: s * 0.26)
                    .background(Circle().fill(Theme.accentDim.opacity(0.6)))
                    .position(c)

                ForEach(cues) { cue in
                    let isPrimary = cue.id == primaryID
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: s * (isPrimary ? 0.15 : 0.08)))
                        .foregroundStyle(cue.group.color.opacity(isPrimary ? 1 : 0.55))
                        .shadow(color: isPrimary ? cue.group.color.opacity(0.8) : .clear, radius: 6)
                        .rotationEffect(.degrees(cue.azimuthDeg))
                        .position(CueDirection.point(c, ring, cue.azimuthDeg))
                        .zIndex(isPrimary ? 1 : 0)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeInOut(duration: 0.35), value: cues)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cues.isEmpty ? "No sounds"
                            : cues.map { "\($0.title), \($0.direction)" }.joined(separator: "; "))
    }
}

/// "Car horn" / "Front-right", or "All quiet".
private struct PrimaryLabel: View {
    let cue: SoundCue?

    var body: some View {
        VStack(spacing: 0) {
            if let cue {
                Label(cue.title, systemImage: cue.symbol)
                    .font(.headline)
                    .foregroundStyle(cue.group.color)
                Text(cue.direction)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("All quiet")
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
                Text(" ").font(.footnote)   // keeps the dial from jumping
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }
}
