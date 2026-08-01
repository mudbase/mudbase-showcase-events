package dev.mudbase.showcase.events.support;

import dev.mudbase.showcase.events.auth.AuthSession;
import dev.mudbase.showcase.events.auth.SessionAuthService;
import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Component;
import org.springframework.ui.Model;

/**
 * Populates the header/nav attributes every Thymeleaf page needs (current user, role flags).
 * Deliberately called explicitly per template-rendering controller method rather than wired as a
 * global {@code @ControllerAdvice @ModelAttribute} - keeps every controller's data needs explicit
 * at the call site, matching the sibling kanban/social/ecommerce ports' own reasoning.
 */
@Component
public class ViewModelHelper {

  private final SessionAuthService sessionAuthService;

  public ViewModelHelper(SessionAuthService sessionAuthService) {
    this.sessionAuthService = sessionAuthService;
  }

  /**
   * Returns the signed-in {@link AuthSession}. Every page in this app other than {@code /login}
   * is behind {@code AuthGateInterceptor}, so this is expected to always be present when called
   * from a gated controller - {@code null} only for the (never-reached in practice, guarded
   * defensively) case of a template rendered outside that gate.
   */
  public AuthSession addLayoutAttributes(Model model, HttpSession session) {
    AuthSession auth = sessionAuthService.current(session).orElse(null);
    model.addAttribute("currentUser", auth);
    model.addAttribute("isSignedIn", auth != null);
    model.addAttribute("currentRole", auth != null ? auth.getRole() : null);
    model.addAttribute("roleLabel", RoleSupport.roleLabel(auth != null ? auth.getRole() : null));
    model.addAttribute("isOrganizer", RoleSupport.isOrganizer(auth != null ? auth.getRole() : null));
    return auth;
  }
}
