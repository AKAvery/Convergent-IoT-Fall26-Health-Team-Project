import Input
import Models
import SwiftUI

/// The four worn pins (design-refs/Devices.png).
struct PinsView: View {
    @State private var profileTab: ProfileTab?
    @State private var pairing = false
    private let session = LiveSession.shared

    var body: some View {
        List {
            Section {
                ForEach(BoxPosition.allCases, id: \.self) { box in
                    PinRow(box: box, link: session.ble.boxes[box] ?? BoxLinkStatus(),
                           streaming: session.status.streamingBox == box)
                }
            } footer: {
                Text(session.summary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Pair a new pin") { pairing = true }
                    .tint(Theme.accent)
            }
            .listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Pins")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { AvatarButton { profileTab = .feed } }
        }
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
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(box.rawValue.capitalized) pin").font(.headline)
                HStack(spacing: 6) {
                    if streaming {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                    }
                    Text(stateText)
                        .font(.subheadline)
                        .foregroundStyle(link.state == .connected ? Theme.text : Theme.secondaryText)
                }
                if link.state == .connected, let db = link.lastPeakDbfs {
                    Text(String(format: "%.0f dBFS", db))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Image(systemName: link.lowBattery ? "battery.25" : "battery.100")
                .foregroundStyle(link.lowBattery ? Theme.urgent : Theme.secondaryText)
                .accessibilityLabel(link.lowBattery ? "Battery low" : "Battery OK")
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}
