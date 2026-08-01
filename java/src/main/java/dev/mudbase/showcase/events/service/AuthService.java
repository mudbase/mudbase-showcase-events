package dev.mudbase.showcase.events.service;

import dev.mudbase.showcase.events.auth.AuthSession;
import dev.mudbase.showcase.events.auth.SessionAuthService;
import dev.mudbase.showcase.events.mudbase.AuthResult;
import dev.mudbase.showcase.events.mudbase.MudbaseAuthClient;
import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Service;

/**
 * Login/logout only - registration is out of scope for this reference port (both demo accounts
 * are pre-provisioned; see plan/build-plan.md "Stack Decisions"), matching the sibling Kanban
 * port's own reasoning.
 */
@Service
public class AuthService {

  private final MudbaseAuthClient authClient;
  private final SessionAuthService sessionAuthService;

  public AuthService(MudbaseAuthClient authClient, SessionAuthService sessionAuthService) {
    this.authClient = authClient;
    this.sessionAuthService = sessionAuthService;
  }

  public AuthSession login(HttpSession session, String email, String password) {
    AuthResult result = authClient.login(email, password);
    sessionAuthService.establish(session, result);
    return sessionAuthService.current(session).orElseThrow();
  }

  public void logout(HttpSession session) {
    sessionAuthService.logout(session);
  }
}
