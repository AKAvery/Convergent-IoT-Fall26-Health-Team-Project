import SwiftUI

/// "Pins / Your Halo devices" (design-refs/Devices.png).
struct PinsView: View {
    @State private var profileTab: ProfileTab?
    @State private var pairing = false

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
                    ForEach(DemoData.pins) { pin in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "paperclip")
                                .font(.title)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 56, height: 56)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accentDim))
                            Text(pin.name).font(.headline)
                            Spacer()
                            Image(systemName: "battery.100")
                                .font(.title3)
                                .foregroundStyle(Theme.secondaryText)
                                .frame(height: 56)
                                .accessibilityLabel("Battery \(pin.battery)%")
                        }
                        .padding(10)
                        .card(radius: 18, stroke: Theme.secondaryText.opacity(0.5))
                    }
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
        .fullScreenCover(isPresented: $pairing) {
            SetupFlowView(onFinish: { pairing = false }, onCancel: { pairing = false })
        }
    }
}
