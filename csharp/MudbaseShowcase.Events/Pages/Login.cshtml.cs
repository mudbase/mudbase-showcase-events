using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Services;

namespace MudbaseShowcase.Events.Pages;

/// <summary>
/// Email+password sign-in, plus two "Sign in as..." quick-fill buttons for the task's demo
/// accounts - mirrors ../../web/src/components/auth/LoginForm.tsx. There is no registration UI in
/// this port (see Services/MudbaseAuthService.cs's doc comment for why) - only these two
/// pre-verified accounts are used.
/// </summary>
public sealed class LoginModel : PageModel
{
    private readonly MudbaseAuthService _authService;

    public LoginModel(MudbaseAuthService authService)
    {
        _authService = authService;
    }

    [BindProperty]
    public LoginInput Input { get; set; } = new();

    public string? ErrorMessage { get; private set; }

    /// <summary>Where to send the visitor after a successful sign-in - RequireMudbaseSessionMiddleware passes its own page URL here so signing in doesn't bounce back to the event list.</summary>
    [BindProperty(SupportsGet = true)]
    public string? ReturnUrl { get; set; }

    public void OnGet()
    {
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid)
        {
            return Page();
        }

        AuthOutcome outcome = await _authService.LoginAsync(Input.Email, Input.Password, cancellationToken);
        return AfterLogin(outcome);
    }

    /// <summary>
    /// The task's two demo accounts, already provisioned on the shared project (see
    /// plan/build-plan.md) - not a secret credential store, just a fast-demo convenience mirroring
    /// the web app's two "Sign in as..." buttons.
    /// </summary>
    public async Task<IActionResult> OnPostQuickLoginAsync(string role, CancellationToken cancellationToken)
    {
        (string Email, string Password)? credentials = role switch
        {
            Rbac.Organizer => ("events.organizer.demo@gmail.com", "DemoTest123!"),
            Rbac.Attendee => ("events.attendee.demo@gmail.com", "DemoTest123!"),
            _ => null,
        };

        if (credentials is null)
        {
            ErrorMessage = "Unknown demo role.";
            return Page();
        }

        AuthOutcome outcome = await _authService.LoginAsync(credentials.Value.Email, credentials.Value.Password, cancellationToken);
        return AfterLogin(outcome);
    }

    private IActionResult AfterLogin(AuthOutcome outcome)
    {
        if (!outcome.Succeeded)
        {
            ErrorMessage = outcome.ErrorMessage ?? "Login failed";
            return Page();
        }

        if (!string.IsNullOrWhiteSpace(ReturnUrl) && Url.IsLocalUrl(ReturnUrl))
        {
            return LocalRedirect(ReturnUrl);
        }

        return RedirectToPage("/Index");
    }

    public sealed class LoginInput
    {
        [Required(ErrorMessage = "Email is required"), EmailAddress(ErrorMessage = "Enter a valid email address")]
        public string Email { get; set; } = string.Empty;

        [Required(ErrorMessage = "Password is required")]
        public string Password { get; set; } = string.Empty;
    }
}
