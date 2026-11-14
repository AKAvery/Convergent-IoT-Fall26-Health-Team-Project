import SwiftUI

/// The round "sounds around you" picture: the wearer in the middle, a coloured arc on the outer
/// ring toward each sound, and a label chip per sound. Used by Welcome, Live, the Profile feed
/// post and the Watch.
struct SoundDial: View {
    var cues: [SoundCue]
    var centerSymbol = "figure.stand"
    var showDistance = true
    var showChips = true
    var compact = false                  // smaller chips (Watch, Profile feed)
    var showBackdrop = true

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = size / 2
            let arcRadius = r * 0.80
            let arcWidth = r * 0.17
            ZStack {
                if showBackdrop {
                    Circle()
                        .fill(Theme.surface.opacity(0.55))
                        .frame(width: size, height: size)
                        .position(c)
                }
                Circle().stroke(Theme.line, lineWidth: 1)
                    .frame(width: arcRadius * 2 + arcWidth, height: arcRadius * 2 + arcWidth)
                    .position(c)
                Circle().stroke(Theme.line, lineWidth: 1)
                    .frame(width: arcRadius * 2 - arcWidth, height: arcRadius * 2 - arcWidth)
                    .position(c)
                Circle().stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: r * 0.95, height: r * 0.95)
                    .position(c)

                ForEach(cues) { cue in
                    CueArc(color: cue.group.color, azimuthDeg: cue.azimuthDeg, radius: arcRadius, width: arcWidth)
                        .position(c)
                }

                Image(systemName: centerSymbol)
                    .font(.system(size: r * 0.2, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: r * 0.42, height: r * 0.42)
                    .background(Circle().fill(Theme.accentDim.opacity(0.6)))
                    .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
                    .shadow(color: Theme.accent.opacity(0.5), radius: 10)
                    .position(c)

                if showChips {
                    ForEach(cues) { cue in
                        CueChip(cue: cue, showDistance: showDistance, compact: compact)
                            .position(chipPoint(c, r, cue.azimuthDeg, in: geo.size))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cues.map { "\($0.title), \($0.direction)" }.joined(separator: "; "))
    }

    /// Chips sit between the wearer and the arc, nudged outward horizontally like the design.
    private func chipPoint(_ c: CGPoint, _ r: CGFloat, _ deg: Double, in size: CGSize) -> CGPoint {
        let p = CueDirection.point(c, r * 0.52, deg)
        let halfW: CGFloat = compact ? 44 : 62
        return CGPoint(x: min(max(p.x, halfW), size.width - halfW), y: p.y)
    }
}

/// A thick arc on the outer ring, ~55° wide, centred on the sound's direction.
struct CueArc: View {
    let color: Color
    let azimuthDeg: Double
    let radius: CGFloat
    let width: CGFloat
    var spanDeg: Double = 55

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: spanDeg / 360)
                .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: width * 1.9))
            Circle()
                .trim(from: 0, to: spanDeg / 360)
                .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: width))
                .shadow(color: color.opacity(0.7), radius: 8)
        }
        .frame(width: radius * 2, height: radius * 2)
        // trim starts at 3 o'clock; rotate so the arc is centred on the azimuth (0° = up).
        .rotationEffect(.degrees(azimuthDeg - spanDeg / 2 - 90))
    }
}

/// "Car horn / 12 m · Front-right" label.
struct CueChip: View {
    let cue: SoundCue
    var showDistance = true
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 7) {
            Image(systemName: cue.symbol)
                .font(.system(size: compact ? 8 : 11, weight: .bold))
                .foregroundStyle(cue.group.color)
                .frame(width: compact ? 15 : 24, height: compact ? 15 : 24)
                .background(RoundedRectangle(cornerRadius: compact ? 4 : 6).fill(cue.group.color.opacity(0.22)))
            VStack(alignment: .leading, spacing: 1) {
                Text(cue.title)
                    .font(.system(size: compact ? 8 : 12, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(cue.detail(showDistance: showDistance))
                    .font(.system(size: compact ? 6 : 9))
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 3 : 5)
        .background(RoundedRectangle(cornerRadius: compact ? 5 : 8).fill(Theme.background.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: compact ? 5 : 8).stroke(cue.group.color.opacity(0.9), lineWidth: 1))
    }
}
