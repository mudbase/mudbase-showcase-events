import SwiftUI

/// The Swift equivalent of `mudbase-provider.tsx`'s bootstrap effect: restore a session from
/// Keychain, then show either the signed-in tab bar or the auth gate. This app requires login
/// before browsing at all (no anonymous/guest session — this project has no public role
/// configured), so there is no third "browsing as guest" branch.
struct RootView: View {
    let config: AppConfig
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        Group {
            if sessionStore.isBootstrapping {
                LoadingView()
            } else if let user = sessionStore.user {
                MainTabView(user: user, config: config)
            } else {
                AuthGateView()
            }
        }
        .task { await sessionStore.bootstrap() }
    }
}
