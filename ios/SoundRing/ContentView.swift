import SwiftUI

/// First launch: Welcome → (Create an account) setup → tabs. Signed in: straight to the tabs.
struct ContentView: View {
    @AppStorage(SettingKey.hasOnboarded) private var hasOnboarded = false
    @State private var showSetup = false

    var body: some View {
        Group { if let n = ZZShot.screen { ZZShot.view(n) } else { appFlow } }
            .tint(Theme.accent)
    }

    @ViewBuilder
    private var appFlow: some View {
        Group {
            if hasOnboarded {
                MainTabsView()
            } else {
                WelcomeView(onSignIn: { hasOnboarded = true },
                            onCreateAccount: { showSetup = true })
                    .fullScreenCover(isPresented: $showSetup) {
                        SetupFlowView(onFinish: {
                            showSetup = false
                            hasOnboarded = true
                        }, onCancel: { showSetup = false })
                    }
            }
        }
    }
}

#Preview {
    ContentView()
}
