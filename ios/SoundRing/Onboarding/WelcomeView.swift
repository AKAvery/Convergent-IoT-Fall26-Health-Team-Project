import SwiftUI

/// design-refs/First_Screen.png.
struct WelcomeView: View {
    let onSignIn: () -> Void
    let onCreateAccount: () -> Void

    var body: some View {
        FillingScrollView {
            VStack(spacing: 0) {
                Text("Halo")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Theme.Space.s)

                SoundDial(cues: DemoData.welcomeScene)
                    .frame(maxWidth: 340)
                    .padding(.vertical, Theme.Space.xl)

                VStack(spacing: Theme.Space.m) {
                    Text("See the sounds\naround you")
                        .font(.largeTitle.bold())
                    Text("Halo shows what each sound is and which direction it came from, using four pins you wear.")
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)

                Spacer(minLength: Theme.Space.xl)

                VStack(spacing: Theme.Space.s) {
                    PrimaryButton(title: "Sign in", action: onSignIn)
                    SecondaryButton(title: "Create an account", action: onCreateAccount)
                }
            }
            .padding(.horizontal, Theme.Space.margin)
            .padding(.bottom, Theme.Space.m)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
    }
}
