import Foundation
import MudbaseSDK

/// Thin wrapper over `AuthenticationAPI` + `MultiRoleFeatureAPI`'s async/await calls. Kept separate
/// from `SessionStore` (which owns observable app state) so the actual network calls stay
/// unit-testable independent of SwiftUI/Observation.
///
/// Unlike the ecommerce/social Swift ports (which only ever self-register one hardcoded role —
/// `customer`/`seller` provisioned out-of-band), this app's own reference web client
/// (`web/src/lib/mudbase.ts`'s `register(role, params)`) takes a role parameter for either
/// `"organizer"` or `"attendee"` — this project genuinely has a role picker on its register screen
/// (`RegisterForm.tsx`), so `registerUser` below does too.
struct AuthGateway: Sendable {
    let projectId: String

    struct LoginResult: Sendable {
        let accessToken: String
        let refreshToken: String
    }

    struct RegisterResult: Sendable {
        /// True when the project requires email verification before a session is issued — in that
        /// case `session`/`user` are both `nil` and the caller shows a "check your email" message
        /// instead.
        let requiresVerification: Bool
        let session: LoginResult?
        let user: AppUser?
    }

    /// `POST /api/auth/local/signup/{role}` — `role` is `.organizer` or `.attendee`, matching the
    /// register screen's role toggle. `agreedToTerms` is enforced client-side by the register
    /// screen's own validation and is also transmitted to the server (Mudbase's registration
    /// validator requires it for a direct signup call).
    func registerUser(role: AppRole, email: String, password: String, firstName: String, lastName: String, agreedToTerms: Bool) async throws(ErrorResponse) -> RegisterResult {
        let response = try await MultiRoleFeatureAPI.registerWithRole(
            role: role.rawValue,
            registerWithRoleRequest: RegisterWithRoleRequest(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                projectId: projectId,
                agreedToTerms: agreedToTerms
            )
        )
        if response.requireVerification == true {
            return RegisterResult(requiresVerification: true, session: nil, user: nil)
        }
        guard let token = response.token,
              let refreshToken = response.refreshToken,
              let responseUser = response.user,
              let user = AppUser(registered: responseUser)
        else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.missingTokenInLoginResponse)
        }
        return RegisterResult(requiresVerification: false, session: LoginResult(accessToken: token, refreshToken: refreshToken), user: user)
    }

    /// `POST /api/auth/local/login`.
    func login(email: String, password: String) async throws(ErrorResponse) -> LoginResult {
        let response = try await AuthenticationAPI.loginLocalUser(
            loginLocalUserRequest: LoginLocalUserRequest(email: email, password: password, projectId: projectId)
        )
        guard let token = response.token, let refreshToken = response.refreshToken else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.missingTokenInLoginResponse)
        }
        return LoginResult(accessToken: token, refreshToken: refreshToken)
    }

    /// `GET /api/auth/local/session` — the only endpoint that returns the project end-user's custom
    /// role (`organizer`/`attendee`), since `LoginLocalUser200ResponseUser` doesn't include it.
    func currentUser() async throws(ErrorResponse) -> AppUser {
        let response = try await AuthenticationAPI.getLocalSession(projectId: projectId)
        guard let userJSON = response.user, let user = AppUser(json: userJSON) else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.malformedSessionUser)
        }
        return user
    }

    /// `POST /api/auth/refresh` — rotates the refresh token on every use (platform-enforced,
    /// single-use); the caller is responsible for persisting the new pair.
    func refresh(refreshToken: String) async throws(ErrorResponse) -> LoginResult {
        let response = try await AuthenticationAPI.refreshToken(refreshTokenRequest: RefreshTokenRequest(refreshToken: refreshToken))
        guard let token = response.token, let newRefreshToken = response.refreshToken else {
            throw ErrorResponse.error(-2, nil, nil, MudbaseClientError.missingTokenInLoginResponse)
        }
        return LoginResult(accessToken: token, refreshToken: newRefreshToken)
    }

    /// `POST /api/auth/local/logout` — best-effort; callers clear local state regardless of outcome.
    func logout() async throws(ErrorResponse) {
        _ = try await AuthenticationAPI.logoutLocalUser()
    }
}

enum MudbaseClientError: Error, Equatable {
    case missingTokenInLoginResponse
    case malformedSessionUser
}
