import Input
import Models
import SwiftUI

/// "Pins / Your Halo devices" (design-refs/Devices.png).
struct PinsView: View {
    @State private var profileTab: ProfileTab?
    @State private var pairing = false
    private let session = LiveSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pins").font(.largeTitle.bold())
                    Text("Your Halo devices").foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                AvatarButton { profileTab = .feed }
            }
            ScrollView {
                VStack(spacing: 18) {
                    ForEach(BoxPosition.allCases, id: \.self) { box in
                        PinRow(box: box, link: session.ble.boxes[box] ?? BoxLinkStatus(),
                               streaming: session.status.streamingBox == box)
                    }
                    Text(session.summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Button { pairing = true } label: {
                Text("Pair New Pin")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 44).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Theme.background)
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $profileTab) { ProfileView(initialTab: $0) }
        .onAppear { session.start() }
        .fullScreenCover(isPresented: $pairing) {
            SetupFlowView(onFinish: { pairing = false }, onCancel: { pairing = false })
        }
    }
}

/// One box: which body position, whether it is connected, its last level, and whether it is the
/// one streaming audio to the classifier.
struct PinRow: View {
    let box: BoxPosition
    let link: BoxLinkStatus
    let streaming: Bool

    private var stateText: String {
        switch link.state {
        case .connected: streaming ? "Connected \u{00B7} listening" : "Connected"
        case .connecting: "Connecting\u{2026}"
        case .notFound: "Not found"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "paperclip")
                .font(.title)
                .foregroundStyle(link.state == .connected ? Theme.accent : Theme.secondaryText)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentDim))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(box.rawValue.capitalized) pin").font(.headline)
                Text(stateText).font(.subheadline).foregroundStyle(Theme.secondaryText)
                if link.state == .connected, let db = link.lastPeakDbfs {
                    Text(String(format: "%.0f dBFS", db)).font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Image(systemName: link.lowBattery ? "battery.25" : "battery.100")
                .font(.title3)
                .foregroundStyle(link.lowBattery ? Theme.urgent : Theme.secondaryText)
                .frame(height: 56)
                .accessibilityLabel(link.lowBattery ? "Battery low" : "Battery OK")
        }
        .padding(10)
        .card(radius: 18, stroke: (streaming ? Theme.accent : Theme.secondaryText).opacity(0.5))
        .accessibilityElement(children: .combine)
    }
}
