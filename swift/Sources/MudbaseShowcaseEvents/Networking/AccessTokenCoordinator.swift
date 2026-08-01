import Foundation
import MudbaseSDK

/// Applies a single 401 → refresh → retry-once policy to every authenticated SDK call in the app,
/// de-duped across concurrent callers via `inFlightRefresh` — refresh tokens rotate on every use
/// (single-use, platform-enforced), so if two requests both hit a 401 at once, only the first
/// refresh call may succeed; the second would present an already-rotated-away token. Ported
/// verbatim from the ecommerce/social Swift ports' `Networking/AccessTokenCoordinator.swift`.
actor AccessTokenCoordinator {
    static let shared = AccessTokenCoordinator()

    private var authGateway: AuthGateway?
    private var tokenStore: KeychainTokenStore?
    private var inFlightRefresh: Task<String, Error>?

    func configure(authGateway: AuthGateway, tokenStore: KeychainTokenStore) {
        self.authGateway = authGateway
        self.tokenStore = tokenStore
    }

    /// Runs `operation`; on a 401, refreshes the access token (or awaits an already-in-flight
    /// refresh from a concurrent caller) and retries exactly once. Any error from the refresh itself
    /// clears the stored session and rethrows the *original* 401, not the refresh's own error — a
    /// caller sees a plain "session expired," never a confusing refresh-endpoint failure.
    func perform<T: Sendable>(_ operation: @Sendable () async throws(ErrorResponse) -> T) async throws(ErrorResponse) -> T {
        do {
            return try await operation()
        } catch let firstError {
            guard case ErrorResponse.error(401, _, _, _) = firstError else { throw firstError }
            do {
                _ = try await refreshedAccessToken()
            } catch {
                tokenStore?.clear()
                MudbaseSDKBootstrap.clearAccessToken()
                throw firstError
            }
            return try await operation()
        }
    }

    private func refreshedAccessToken() async throws -> String {
        if let inFlightRefresh {
            return try await inFlightRefresh.value
        }

        guard let authGateway, let tokenStore, let stored = tokenStore.load() else {
            throw MudbaseClientError.missingTokenInLoginResponse
        }

        let task = Task<String, Error> {
            let result = try await authGateway.refresh(refreshToken: stored.refreshToken)
            tokenStore.save(.init(accessToken: result.accessToken, refreshToken: result.refreshToken))
            MudbaseSDKBootstrap.setAccessToken(result.accessToken)
            return result.accessToken
        }
        inFlightRefresh = task

        defer { inFlightRefresh = nil }
        return try await task.value
    }
}
