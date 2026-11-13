import SwiftUI

/// The round "sounds around you" picture, seen from above: the wearer in the middle, an arc on
/// the ring toward each sound in its group colour, and a label chip per sound. A short tick at
/// the top of the ring marks "in front of you". Used by Welcome, Live and the Profile feed post.
struct SoundDial: View {
    var cues: [SoundCue]
    var centerSymbol = "figure.stand"
    var showDistance = true
    var showChips = true
    var compact = false                  // smaller chips (Profile feed)

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = size / 2
            let arcRadius = r * 0.86
            let arcWidth = r * 0.09
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 1)
                    .frame(width: arcRadius * 2, height: arcRadius * 2)
                    .position(c)
                Capsule()
                    .fill(Theme.secondaryText)
                    .frame(width: 2, height: arcWidth + 8)
                    .position(x: c.x, y: c.y - arcRadius)

                ForEach(cues) { cue in
                    CueArc(color: cue.group.color, azimuthDeg: cue.azimuthDeg, radius: arcRadius, width: arcWidth)
                        .position(c)
                }

                Image(systemName: centerSymbol)
                    .font(.system(size: r * 0.18))
                    .foregroundStyle(Theme.text)
                    .position(c)

                if showChips {
                    ForEach(cues) { cue in
                        CueChip(cue: cue, showDistance: showDistance, compact: compact)
                            .position(chipPoint(c, r, cue.azimuthDeg, in: geo.size))
                            .zIndex(cue.isUrgent ? 1 : 0)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cues.isEmpty ? "No sounds right now"
                            : cues.map { "\($0.title), \($0.direction)" }.joined(separator: "; "))
    }

    /// Chips sit between the wearer and the arc, kept inside the dial horizontally.
    private func chipPoint(_ c: CGPoint, _ r: CGFloat, _ deg: Double, in size: CGSize) -> CGPoint {
        let p = CueDirection.point(c, r * 0.52, deg)
        let halfW: CGFloat = compact ? 52 : 68
        return CGPoint(x: min(max(p.x, halfW), size.width - halfW), y: p.y)
    }
}

/// A solid arc on the ring, ~50° wide, centred on the sound's direction.
struct CueArc: View {
    let color: Color
    let azimuthDeg: Double
    let radius: CGFloat
    let width: CGFloat
    var spanDeg: Double = 50

    var body: some View {
        Circle()
            .trim(from: 0, to: spanDeg / 360)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .butt))
            .frame(width: radius * 2, height: radius * 2)
            // trim starts at 3 o'clock; rotate so the arc is centred on the azimuth (0° = up).
            .rotationEffect(.degrees(azimuthDeg - spanDeg / 2 - 90))
    }
}

/// "Car horn / 12 m · Front-right" label. Urgent sounds get a filled chip so they can't be missed.
struct CueChip: View {
    let cue: SoundCue
    var showDistance = true
    var compact = false

    var body: some View {
        let urgent = cue.isUrgent
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip)
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: cue.symbol)
                .font((compact ? Font.caption2 : .footnote).weight(.semibold))
                .foregroundStyle(urgent ? Theme.onAccent : cue.group.color)
            VStack(alignment: .leading, spacing: 0) {
                Text(cue.title)
                    .font((compact ? Font.caption2 : .caption).weight(.semibold))
                    .foregroundStyle(urgent ? Theme.onAccent : Theme.text)
                Text(cue.detail(showDistance: showDistance))
                    .font(.caption2)
                    .foregroundStyle(urgent ? Theme.onAccent : Theme.secondaryText)
            }
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 5)
        .background(shape.fill(urgent ? cue.group.color : Theme.surface))
        .overlay(shape.stroke(urgent ? Color.clear : Theme.line, lineWidth: 1))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}
