using Microsoft.AspNetCore.Http;
using MudbaseShowcase.Events.Services;

namespace MudbaseShowcase.Events.Infrastructure;

/// <summary>
/// Runs once per request, right after the session cookie middleware. This app has no anonymous/
/// guest session at all - every role (organizer/attendee) must be signed in, because Mudbase's own
/// collection permissions 401 an unauthenticated read on this project (see plan/build-plan.md
/// "Auth Flow" - the reference Next.js app makes the identical decision for the identical reason).
/// Any request with no Mudbase token cached in the session, for a path other than the login/logout
/// pages, the error page, or static assets, is redirected to /Login with a ReturnUrl back to the
/// page the visitor was trying to reach - this is the server-side equivalent of the reference
/// app's client-side AuthGate.
/// </summary>
public sealed class RequireMudbaseSessionMiddleware
{
    private readonly RequestDelegate _next;

    public RequireMudbaseSessionMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context, MudbaseSessionAccessor session)
    {
        if (RequiresSession(context.Request.Path) && !session.HasToken)
        {
            string returnUrl = context.Request.Path + context.Request.QueryString;
            context.Response.Redirect($"/Login?ReturnUrl={Uri.EscapeDataString(returnUrl)}");
            return;
        }

        await _next(context);
    }

    private static bool RequiresSession(PathString path)
    {
        if (path.StartsWithSegments("/login", StringComparison.OrdinalIgnoreCase)) return false;
        if (path.StartsWithSegments("/logout", StringComparison.OrdinalIgnoreCase)) return false;
        if (path.StartsWithSegments("/error", StringComparison.OrdinalIgnoreCase)) return false;
        if (IsStaticAsset(path)) return false;
        return true;
    }

    private static bool IsStaticAsset(PathString path) =>
        path.StartsWithSegments("/css") ||
        path.StartsWithSegments("/js") ||
        path.StartsWithSegments("/lib") ||
        path.StartsWithSegments("/favicon.ico");
}
