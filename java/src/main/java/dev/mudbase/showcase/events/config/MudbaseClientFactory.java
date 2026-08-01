package dev.mudbase.showcase.events.config;

import dev.mudbase.sdk.ApiClient;
import dev.mudbase.sdk.api.AuthenticationApi;
import dev.mudbase.sdk.api.DataApi;
import java.util.concurrent.TimeUnit;
import okhttp3.OkHttpClient;
import org.springframework.stereotype.Component;

/**
 * Builds a fresh {@link ApiClient} per call, all sharing one connection-pooled {@link
 * OkHttpClient}. The generated SDK's {@code ApiClient} carries mutable per-instance auth state
 * (bearer token), so it is not safe to share a single {@code ApiClient} across concurrent Spring
 * MVC requests for different signed-in users - a fresh, cheap {@code ApiClient} wrapper per call
 * (backed by the same pooled HTTP client, so no repeated TCP/TLS handshakes) is the correct
 * pattern here. Ported verbatim from the sibling kanban/social/ecommerce Java showcases.
 */
@Component
public class MudbaseClientFactory {

  private final MudbaseProperties properties;
  private final OkHttpClient sharedHttpClient;

  public MudbaseClientFactory(MudbaseProperties properties) {
    this.properties = properties;
    this.sharedHttpClient =
        new OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build();
  }

  /** A client with no bearer token attached - only usable against no-auth-required endpoints. */
  public ApiClient anonymousClient() {
    ApiClient client = new ApiClient(sharedHttpClient);
    client.setBasePath(properties.getBaseUrl());
    return client;
  }

  /** A client authenticated as the given end-user (organizer/attendee) JWT. */
  public ApiClient clientFor(String bearerToken) {
    ApiClient client = anonymousClient();
    if (bearerToken != null && !bearerToken.isBlank()) {
      client.setBearerToken(bearerToken);
    }
    return client;
  }

  public AuthenticationApi authApi(String bearerTokenOrNull) {
    return new AuthenticationApi(clientFor(bearerTokenOrNull));
  }

  public DataApi dataApi(String bearerTokenOrNull) {
    return new DataApi(clientFor(bearerTokenOrNull));
  }

  /** Shared OkHttp client, reused for the raw (non-generated) calls the SDK doesn't cover. */
  public OkHttpClient rawHttpClient() {
    return sharedHttpClient;
  }

  public String baseUrl() {
    return properties.getBaseUrl();
  }

  public String projectId() {
    return properties.getProjectId();
  }
}
