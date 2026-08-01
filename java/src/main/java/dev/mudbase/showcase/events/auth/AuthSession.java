package dev.mudbase.showcase.events.auth;

import java.io.Serializable;

/**
 * The signed-in user's Mudbase identity, held server-side in the Spring {@code HttpSession} - the
 * JWT never reaches client JS (rendered pages get plain HTML/CSS only, no token in scope). Like
 * the sibling Kanban port, this app has no anonymous/guest session variant: every one of the two
 * roles (organizer/attendee) requires a real sign-in, since Mudbase's own collection permissions
 * 401 an unauthenticated request even for read-only event access - see plan/build-plan.md
 * "Auth Model".
 */
public class AuthSession implements Serializable {

  private static final long serialVersionUID = 1L;

  private final String token;
  private final String userId;
  private final String email;
  private final String firstName;
  private final String lastName;
  private final String role;
  private final String refreshToken;

  public AuthSession(
      String token, String userId, String email, String firstName, String lastName, String role, String refreshToken) {
    this.token = token;
    this.userId = userId;
    this.email = email;
    this.firstName = firstName;
    this.lastName = lastName;
    this.role = role;
    this.refreshToken = refreshToken;
  }

  /**
   * Immutable copy carrying a rotated access/refresh token pair after a successful {@code
   * POST /api/auth/refresh} - every other field (identity, role) is preserved since a token
   * refresh never changes who the caller is.
   */
  public AuthSession withRefreshedToken(String newToken, String newRefreshToken) {
    return new AuthSession(newToken, userId, email, firstName, lastName, role, newRefreshToken);
  }

  public String getToken() {
    return token;
  }

  public String getUserId() {
    return userId;
  }

  public String getEmail() {
    return email;
  }

  public String getFirstName() {
    return firstName;
  }

  public String getLastName() {
    return lastName;
  }

  /** `${firstName} ${lastName}`.trim(), matching the reference web app's userName/actorName display logic. */
  public String getDisplayName() {
    String joined = String.join(" ", firstName != null ? firstName : "", lastName != null ? lastName : "").trim();
    return joined.isBlank() ? (email != null ? email : "Someone") : joined;
  }

  public String getRole() {
    return role;
  }

  public String getRefreshToken() {
    return refreshToken;
  }

  public boolean isSignedIn() {
    return userId != null;
  }
}
