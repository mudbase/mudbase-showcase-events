package dev.mudbase.showcase.events.auth;

import dev.mudbase.showcase.events.mudbase.AuthResult;
import dev.mudbase.showcase.events.mudbase.MudbaseAuthClient;
import jakarta.servlet.http.HttpSession;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * Bridges the Spring {@code HttpSession} to Mudbase auth. The JWT lives here, server-side, for
 * the life of the session - never sent to client JS (rendered pages get plain HTML/CSS only, no
 * token in scope).
 *
 * <p>Ported from {@code mudbase-showcase-kanban/java}'s {@code SessionAuthService} (itself ported
 * from the ecommerce/social showcases), including the already-fixed {@link
 * #recoverFromUnauthorized} - reused verbatim rather than rediscovered, per the task's explicit
 * instruction. This app's own {@code EventController#detail} (which resolves an event and its
 * live confirmed-booking count in two sequential {@link
 * dev.mudbase.showcase.events.mudbase.MudbaseDataClient} calls from one session snapshot) is
 * exactly the shape that bug required: see that method's javadoc for the full bug/fix history.
 */
@Component
public class SessionAuthService {

  static final String SESSION_KEY = "mudbase.auth";

  private final MudbaseAuthClient authClient;

  public SessionAuthService(MudbaseAuthClient authClient) {
    this.authClient = authClient;
  }

  /** Every role in this app must be genuinely signed in - there is no anonymous/guest variant. */
  public Optional<AuthSession> current(HttpSession session) {
    Object attribute = session.getAttribute(SESSION_KEY);
    return attribute instanceof AuthSession auth ? Optional.of(auth) : Optional.empty();
  }

  public void establish(HttpSession session, AuthResult result) {
    session.setAttribute(
        SESSION_KEY,
        new AuthSession(
            result.getToken(),
            result.getUserId(),
            result.getEmail(),
            result.getFirstName(),
            result.getLastName(),
            result.getCustomRole(),
            result.getRefreshToken()));
  }

  public void logout(HttpSession session) {
    current(session).ifPresent(auth -> authClient.logout(auth.getToken()));
    session.removeAttribute(SESSION_KEY);
  }

  /**
   * Recovers from a 401 on an ordinary data/collection call by exchanging the stored refresh
   * token for a new access token, once. Called by {@link
   * dev.mudbase.showcase.events.mudbase.MudbaseDataClient} when a request bearing {@code
   * failedToken} comes back unauthorized.
   *
   * <p><b>Why a token mismatch does not mean "nothing to do."</b> This is the fix the sibling
   * {@code mudbase-showcase-ecommerce/java} port discovered and applied - reused here verbatim
   * rather than rediscovered, per the task's explicit instruction. Several call sites in this app
   * (most notably {@code EventController#detail}, which reads the signed-in {@link AuthSession}
   * once and passes that same snapshot's access token into an event-lookup call and a
   * confirmed-count call back to back) read the session once and reuse its token across multiple
   * {@link dev.mudbase.showcase.events.mudbase.MudbaseDataClient} calls. If the token was expired,
   * the *first* of those calls lands here, refreshes, and updates the session - but the *second*
   * call still carries the pre-refresh token, so it 401s too and lands here again with a {@code
   * failedToken} that no longer matches {@code current.getToken()} (the first call already moved
   * it forward). Treating that as "someone else already fixed it, give up" discards a perfectly
   * good, just-refreshed session and forces a spurious "session expired" logout on every
   * multi-call page for any user whose access token happened to expire mid-request. The correct
   * read of a mismatch is the opposite: the session already holds a token newer than the one that
   * failed, so hand that back for an immediate retry instead of refreshing again. If it turns out
   * to *also* be stale (a real concurrent-request race, or the mismatch reflects a session some
   * other tab already logged out of), the retry simply fails with its own 401 and propagates
   * normally - this never masks a genuine failure, it only avoids inventing one.
   *
   * <p>Returns empty (no retry attempted) only when there is truly nothing left to recover with:
   * no session at all, the token that failed is still the one on file but there is no refresh
   * token to exchange it with, or the refresh call itself was rejected (refresh token
   * invalid/expired/already reused) - the caller is expected to treat the original 401 as final
   * in those cases.
   */
  public Optional<AuthSession> recoverFromUnauthorized(HttpSession session, String failedToken) {
    Optional<AuthSession> currentOpt = current(session);
    if (currentOpt.isEmpty()) {
      return Optional.empty();
    }
    AuthSession current = currentOpt.get();
    if (!current.getToken().equals(failedToken)) {
      // An earlier call in this same request (most often) or a concurrent request (occasionally)
      // already refreshed this session past the token that just failed - hand back the session's
      // current token so the caller retries with it, rather than declaring the request a lost
      // cause. See the method javadoc above for why this is the safe reading of a mismatch.
      return Optional.of(current);
    }
    if (current.getRefreshToken() == null) {
      // The token that failed is still the one on file, but there is nothing to exchange it
      // with (shouldn't happen once establish() always stores a refresh token, but fail safe
      // rather than throwing here).
      return Optional.empty();
    }
    try {
      AuthResult refreshed = authClient.refresh(current.getRefreshToken());
      AuthSession updated = current.withRefreshedToken(refreshed.getToken(), refreshed.getRefreshToken());
      session.setAttribute(SESSION_KEY, updated);
      return Optional.of(updated);
    } catch (RuntimeException refreshFailure) {
      // The refresh token itself is invalid/expired/reused - nothing left to recover with. Leave
      // the stale session in place; GlobalExceptionHandler's existing 401 handling (logout +
      // redirect to /login) is the correct terminal behavior in that case.
      return Optional.empty();
    }
  }
}
