import Foundation
import MudbaseSDK

/// Owns the app's auth state end to end: bootstrap-from-Keychain at launch, login, register (role
/// picker — `organizer` or `attendee`, unlike the ecommerce/social ports' single hardcoded role),
/// logout, and one-shot refresh-on-401. The SwiftUI equivalent of `web/src/lib/mudbase-provider.tsx`
/// + `web/src/hooks/useAuth.ts` combined, minus the anonymous-guest session — this project has no
/// public role configured (see `web/plan/build-plan.md` "Auth Flow"), so an unauthenticated visitor
/// sees a sign-in prompt, not a bootstrapped guest session.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: AppUser?
    @Published private(set) var isBootstrapping = true

    private let authGateway: AuthGateway
    private let tokenStore: KeychainTokenStore

    init(config: AppConfig, tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.authGateway = AuthGateway(projectId: config.projectId)
        self.tokenStore = tokenStore
    }

    var isSignedIn: Bool { user != nil }

    /// Called once at app launch. Configures the shared `AccessTokenCoordinator` unconditionally
    /// (even when there's no stored session yet), since it must be ready before *any* authenticated
    /// call in the app, including ones made later this same session after a fresh login/register,
    /// not just this bootstrap's own restore attempt. Then restores a stored token pair (if any),
    /// validating it against the session endpoint; a 401 (expired access token) is transparently
    /// refreshed and retried once by the coordinator.
    func bootstrap() async {
        defer { isBootstrapping = false }
        await AccessTokenCoordinator.shared.configure(authGateway: authGateway, tokenStore: tokenStore)

        guard let stored = tokenStore.load() else { return }
        MudbaseSDKBootstrap.setAccessToken(stored.accessToken)

        let gateway = authGateway
        do {
            user = try await AccessTokenCoordinator.shared.perform { () async throws(ErrorResponse) in
                try await gateway.currentUser()
            }
        } catch {
            // Only treat this as "the session is actually invalid" for a 401 that survived the
            // coordinator's own refresh attempt (it only refreshes 401s, and already clears the
            // stored session itself when that refresh fails) — anything else (offline, a transient
            // 5xx) is left alone so the still-good token in the Keychain gets another chance on the
            // next launch instead of forcing a real sign-out over a network blip.
            if case ErrorResponse.error(401, _, _, _) = error {
                tokenStore.clear()
                MudbaseSDKBootstrap.clearAccessToken()
            }
            user = nil
        }
    }

    func login(email: String, password: String) async -> Result<Void, MudbaseAPIError.DisplayableError> {
        do {
            let result = try await authGateway.login(email: email, password: password)
            tokenStore.save(.init(accessToken: result.accessToken, refreshToken: result.refreshToken))
            MudbaseSDKBootstrap.setAccessToken(result.accessToken)
            user = try await authGateway.currentUser()
            return .success(())
        } catch {
            return .failure(MudbaseAPIError.map(error))
        }
    }

    enum RegisterOutcome: Equatable {
        case signedIn
        case verificationRequired(message: String)
        case failure(message: String)
    }

    /// `role` comes from the register screen's own toggle (`organizer`/`attendee`) — this app,
    /// unlike the ecommerce/social ports, has a genuine role picker rather than one hardcoded
    /// self-signup role.
    func register(role: AppRole, email: String, password: String, firstName: String, lastName: String, agreedToTerms: Bool) async -> RegisterOutcome {
        do {
            let result = try await authGateway.registerUser(
                role: role,
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                agreedToTerms: agreedToTerms
            )
            if result.requiresVerification {
                return .verificationRequired(message: "Account created — check your email to verify it, then sign in.")
            }
            guard let session = result.session, let registeredUser = result.user else {
                return .failure(message: "Account created, but we couldn't sign you in automatically. Please sign in.")
            }
            tokenStore.save(.init(accessToken: session.accessToken, refreshToken: session.refreshToken))
            MudbaseSDKBootstrap.setAccessToken(session.accessToken)
            user = registeredUser
            return .signedIn
        } catch {
            let displayable = MudbaseAPIError.map(error)
            if displayable.code == "EMAIL_VERIFICATION_REQUIRED" {
                return .verificationRequired(message: "Account created — check your email to verify it, then sign in.")
            }
            return .failure(message: displayable.message)
        }
    }

    func logout() async {
        _ = try? await authGateway.logout()
        tokenStore.clear()
        MudbaseSDKBootstrap.clearAccessToken()
        user = nil
    }
}
