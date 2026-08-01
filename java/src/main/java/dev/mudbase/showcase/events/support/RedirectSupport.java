package dev.mudbase.showcase.events.support;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * Guards every user-supplied {@code redirect} query/form parameter against open-redirect abuse.
 * Only a same-origin relative path starting with a single {@code /} is accepted; a full URL, a
 * protocol-relative {@code //host/path} (browsers treat that as same-scheme-different-host), or a
 * blank value all fall back to the caller's own default. Ported verbatim from the sibling kanban/
 * social/ecommerce showcases.
 */
public final class RedirectSupport {

  private RedirectSupport() {}

  public static String safe(String candidate, String fallback) {
    if (candidate == null || candidate.isBlank()) {
      return fallback;
    }
    if (!candidate.startsWith("/") || candidate.startsWith("//") || candidate.contains("://")) {
      return fallback;
    }
    return candidate;
  }

  /**
   * Builds a `/login?redirect=...` target with the destination path properly query-encoded - a
   * destination that itself carries a query string would otherwise produce an ambiguous nested
   * `?`/`&` sequence in the resulting URL.
   */
  public static String loginRedirectTo(String destinationPath) {
    return "/login?redirect=" + URLEncoder.encode(destinationPath, StandardCharsets.UTF_8);
  }
}
