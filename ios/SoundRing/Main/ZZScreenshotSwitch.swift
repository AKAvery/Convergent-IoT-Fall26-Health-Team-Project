import SwiftUI
enum ZZShot {
    static let screen = UserDefaults.standard.string(forKey: "screen")
    @MainActor @ViewBuilder static func view(_ n: String) -> some View {
        switch n {
        case "welcome": WelcomeView(onSignIn: {}, onCreateAccount: {})
        case "find": SetupFlowView(startAt: .find, onFinish: {}, onCancel: {})
        case "connect": SetupFlowView(startAt: .connect, onFinish: {}, onCancel: {})
        case "align": SetupFlowView(startAt: .align, onFinish: {}, onCancel: {})
        case "home": MainTabsView(initial: .home)
        case "live": MainTabsView(initial: .live)
        case "pins": MainTabsView(initial: .pins)
        case "settings": MainTabsView(initial: .settings)
        case "feed": NavigationStack { ProfileView(initialTab: .feed) }
        case "edit": NavigationStack { ProfileView(initialTab: .edit) }
        case "ecosystem": NavigationStack { ProfileView(initialTab: .ecosystem) }
        default: MainTabsView()
        }
    }
}
