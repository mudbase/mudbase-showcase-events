import SwiftUI

/// Shown whenever there is no signed-in user. This app requires login before browsing at all (no
/// anonymous/guest session — this project has no public role configured), so this is the very
/// first screen a fresh install sees.
struct AuthGateView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var mode: Mode = .login

    private enum Mode { case register, login }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Mudbase Events")
                        .font(.title2.bold())
                    Text("Every event, booking, and check-in on this screen is served by a real Mudbase project.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 24)
                .padding(.bottom, 12)

                Group {
                    switch mode {
                    case .register:
                        RegisterView(sessionStore: sessionStore, onSwitchToLogin: { mode = .login })
                    case .login:
                        LoginView(sessionStore: sessionStore, onSwitchToRegister: { mode = .register })
                    }
                }
            }
        }
    }
}
