package dev.mudbase.showcase.events.mudbase;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.mudbase.showcase.events.config.MudbaseClientFactory;
import dev.mudbase.sdk.ApiException;
import dev.mudbase.sdk.api.AuthenticationApi;
import dev.mudbase.sdk.model.RefreshToken200Response;
import dev.mudbase.sdk.model.RefreshTokenRequest;
import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.Map;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import org.springframework.stereotype.Component;

/**
 * Auth calls against a provisioned Mudbase project: login, logout, and refresh. No registration
 * here and no anonymous/guest session - every one of the two roles (organizer/attendee) must sign
 * in, since Mudbase's own collection permissions 401 an unauthenticated request even for read-only
 * event access. See plan/build-plan.md "Auth Model".
 *
 * <p><b>Why login bypasses the generated SDK method.</b> {@code AuthenticationApi.loginLocalUser}
 * deserializes its response with the generated {@code LoginLocalUser200ResponseUser} model via
 * Gson, which hard-fails with an {@code IllegalArgumentException} the instant the response JSON
 * contains any property the model doesn't declare. Every account created through this project's
 * Multi-Role feature - i.e. both organizer/attendee accounts - gets a login response whose {@code
 * user} object carries both {@code role} and {@code customRole}; the generated model only
 * declares {@code role}. This is the exact same bug the sibling {@code
 * mudbase-showcase-kanban/java}, {@code mudbase-showcase-ecommerce/java}, and {@code
 * mudbase-showcase-social/java} ports already found and fixed against this same backend - reused
 * here rather than rediscovered, per the task's explicit instruction. Fixed the same way: a raw
 * call over the SDK's own shared {@code OkHttpClient}, same base path and bearer header, parsed
 * leniently with Jackson's {@code ignoreUnknown} instead of the strict generated Gson model.
 */
@Component
public class MudbaseAuthClient {

  private static final ObjectMapper MAPPER = new ObjectMapper();

  private final MudbaseClientFactory clientFactory;

  public MudbaseAuthClient(MudbaseClientFactory clientFactory) {
    this.clientFactory = clientFactory;
  }

  public AuthResult login(String email, String password) {
    Map<String, Object> body = new LinkedHashMap<>();
    body.put("email", email);
    body.put("password", password);
    body.put("projectId", clientFactory.projectId());

    String requestJson;
    try {
      requestJson = MAPPER.writeValueAsString(body);
    } catch (Exception e) {
      throw new IllegalStateException("Could not serialize login request", e);
    }

    OkHttpClient httpClient = clientFactory.rawHttpClient();
    Request request =
        new Request.Builder()
            .url(clientFactory.baseUrl() + "/api/auth/local/login")
            .post(RequestBody.create(requestJson, MediaType.parse("application/json")))
            .build();

    try (Response response = httpClient.newCall(request).execute()) {
      String responseBody = response.body() != null ? response.body().string() : "";
      if (!response.isSuccessful()) {
        throw MudbaseApiException.fromRawBody(response.code(), responseBody);
      }
      LoginPayload payload = MAPPER.readValue(responseBody, LoginPayload.class);
      LoginPayload.User user = payload.user;
      return new AuthResult(
          payload.token,
          user != null ? user.id : null,
          user != null ? user.email : email,
          user != null ? user.firstName : null,
          user != null ? user.lastName : null,
          // Real Multi-Role accounts carry both "role" and "customRole" on this response - see
          // class javadoc. customRole is the project app-role this app cares about (organizer/
          // attendee); fall back to role only for an account shape that predates it.
          user != null && user.customRole != null ? user.customRole : (user != null ? user.role : null),
          payload.refreshToken);
    } catch (IOException e) {
      throw new MudbaseApiException("Could not reach Mudbase to log in", 502, null, e);
    }
  }

  public void logout(String bearerToken) {
    AuthenticationApi authApi = clientFactory.authApi(bearerToken);
    try {
      authApi.logoutLocalUser();
    } catch (ApiException e) {
      // Best-effort revoke: a failed server-side revoke must never block the user from being
      // signed out locally.
    }
  }

  /**
   * Exchanges a stored refresh token for a new access/refresh token pair. Used by {@link
   * dev.mudbase.showcase.events.auth.SessionAuthService#recoverFromUnauthorized} to transparently
   * recover from a 401 caused by an expired access token. Mudbase rotates the refresh token on
   * every use (the previous one is invalidated - reuse is treated as a stolen-token signal), so
   * the caller must persist the {@code refreshToken} on this result, not just the {@code token}.
   */
  public AuthResult refresh(String refreshToken) {
    AuthenticationApi authApi = clientFactory.authApi(null);
    RefreshTokenRequest request = new RefreshTokenRequest().refreshToken(refreshToken);
    try {
      RefreshToken200Response response = authApi.refreshToken(request);
      return new AuthResult(
          response.getToken(),
          null,
          null,
          null,
          null,
          null,
          response.getRefreshToken() != null ? response.getRefreshToken() : refreshToken);
    } catch (ApiException e) {
      throw MudbaseApiException.from(e);
    }
  }

  /**
   * Hand-written mirror of LoginLocalUser200Response, deliberately Jackson-lenient ({@code
   * ignoreUnknown}) rather than the generated Gson model's strict field validation - see class
   * javadoc. Declares both {@code role} and {@code customRole} since real Multi-Role accounts'
   * login responses carry both.
   */
  @JsonIgnoreProperties(ignoreUnknown = true)
  private static class LoginPayload {
    public String message;
    public String token;
    public String refreshToken;
    public Integer expiresIn;
    public User user;

    @JsonIgnoreProperties(ignoreUnknown = true)
    static class User {
      public String id;
      public String email;
      public String firstName;
      public String lastName;
      public String role;
      public String customRole;
      public Boolean emailVerified;
      public Boolean twoFactorEnabled;
    }
  }
}
