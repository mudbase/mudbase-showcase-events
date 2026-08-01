package dev.mudbase.showcase.events.web;

import dev.mudbase.showcase.events.mudbase.MudbaseApiException;
import dev.mudbase.showcase.events.service.AuthService;
import dev.mudbase.showcase.events.support.RedirectSupport;
import dev.mudbase.showcase.events.support.ViewModelHelper;
import dev.mudbase.showcase.events.web.dto.LoginRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

/**
 * Email/password sign-in only - there is no registration UI in this reference port (both demo
 * accounts are pre-provisioned, see plan/build-plan.md), matching the sibling Kanban port's own
 * reasoning. Ships two "Sign in as…" quick-fill forms on the login page alongside the normal
 * form, for fast demoing without retyping credentials - they post to this exact same handler,
 * since Spring binds `email`/`password` request parameters identically regardless of which form
 * on the page submitted them.
 */
@Controller
public class AuthController {

  private final AuthService authService;
  private final ViewModelHelper viewModelHelper;

  public AuthController(AuthService authService, ViewModelHelper viewModelHelper) {
    this.authService = authService;
    this.viewModelHelper = viewModelHelper;
  }

  @GetMapping("/login")
  public String loginForm(
      @RequestParam(value = "redirect", required = false) String redirect, Model model, HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!model.containsAttribute("loginRequest")) {
      model.addAttribute("loginRequest", new LoginRequest());
    }
    model.addAttribute("redirectTo", redirect);
    return "auth/login";
  }

  @PostMapping("/login")
  public String login(
      @Valid @ModelAttribute("loginRequest") LoginRequest form,
      BindingResult bindingResult,
      @RequestParam(value = "redirect", required = false) String redirect,
      Model model,
      HttpSession session) {
    viewModelHelper.addLayoutAttributes(model, session);
    if (!bindingResult.hasErrors()) {
      try {
        authService.login(session, form.getEmail(), form.getPassword());
        return "redirect:" + RedirectSupport.safe(redirect, "/");
      } catch (MudbaseApiException e) {
        model.addAttribute("authError", e.getMessage());
      }
    }
    model.addAttribute("redirectTo", redirect);
    return "auth/login";
  }

  @PostMapping("/logout")
  public String logout(HttpSession session) {
    authService.logout(session);
    return "redirect:/login";
  }
}
