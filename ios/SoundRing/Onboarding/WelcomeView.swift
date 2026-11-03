import SwiftUI

/// design-refs/First_Screen.png.
struct WelcomeView: View {
    let onSignIn: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "eyeglasses")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accentDim))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.accent, lineWidth: 1.5))
                Text("Halo").font(.title2.bold())
            }
            .padding(.top, 8)

            SoundDial(cues: DemoData.welcomeScene)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)

            Text("See the sounds\naround you")
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Halo turns sound into visual cues, so you always know what\u{2019}s happening around you and where it\u{2019}s coming from.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 12)
                .padding(.horizontal, 8)

            HStack(spacing: 6) {
                Capsule().fill(Theme.accent).frame(width: 20, height: 6)
                Circle().fill(Theme.secondaryText.opacity(0.5)).frame(width: 6, height: 6)
                Circle().fill(Theme.secondaryText.opacity(0.5)).frame(width: 6, height: 6)
            }
            .padding(.vertical, 24)
            .accessibilityHidden(true)

            Spacer(minLength: 0)
            PrimaryButton(title: "Sign in", action: onSignIn)
            Text("Or").font(.footnote).foregroundStyle(Theme.secondaryText).padding(.vertical, 6)
            SecondaryButton(title: "Create an account", action: onCreateAccount)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .foregroundStyle(.white)
    }
}
