import SwiftUI

/// Page 2: every sound right now, most important first. One line each: icon, name, direction arrow.
struct WatchListView: View {
    let feed: WatchFeed

    var body: some View {
        List {
            if feed.cues.isEmpty {
                Text("All quiet")
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Color.clear)
            }
            ForEach(feed.ranked) { cue in
                HStack(spacing: 8) {
                    Image(systemName: cue.symbol)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(cue.group.color)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(cue.group.color.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cue.title).font(.body.weight(.semibold))
                        Text(cue.direction).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Image(systemName: "location.north.fill")
                        .font(.footnote)
                        .foregroundStyle(cue.group.color)
                        .rotationEffect(.degrees(cue.azimuthDeg))
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Sounds")
    }
}
