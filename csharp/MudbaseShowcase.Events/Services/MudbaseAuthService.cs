using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Mudbase.Sdk.Api;
using Mudbase.Sdk.Model;
using MudbaseShowcase.Events.Models;
using MudbaseShowcase.Events.Options;

namespace MudbaseShowcase.Events.Services;

/// <summary>
/// Login, session refresh, and logout only - no self-registration UI. Unlike the reference
/// Next.js app (which does expose a `/register` page), this port deliberately omits it: the
/// generated Mudbase C# SDK's `RegisterLocalUserAsync` targets the project's single default-role
/// signup endpoint (`POST /api/auth/local/register`), not the per-role `POST
/// /api/auth/local/signup/:role` path the reference app's hand-rolled TS client calls directly -
/// there is no generated SDK method for the role-scoped signup route this project's two custom
/// roles ("organizer"/"attendee") require. The task's feature list doesn't call for a signup flow
/// either, and the two demo accounts already exist and are pre-verified, so this mirrors the
/// sibling Kanban port's identical, explicitly-documented scope decision rather than
/// reintroducing a code path the SDK doesn't cleanly support. See plan/build-plan.md.
///
/// Like the sibling Kanban port, every one of this app's roles must sign in - Mudbase's own
/// collection permissions 401 an unauthenticated request on this project (see
/// plan/build-plan.md). Every call here goes through the generated SDK directly - no raw-
/// HttpClient workarounds.
/// </summary>
public sealed class MudbaseAuthService
{
    private readonly IAuthenticationApi _authApi;
    private readonly MudbaseSessionAccessor _session;
    private readonly MudbaseOptions _options;
    private readonly ILogger<MudbaseAuthService> _logger;

    public MudbaseAuthService(
        IAuthenticationApi authApi,
        MudbaseSessionAccessor session,
        IOptions<MudbaseOptions> options,
        ILogger<MudbaseAuthService> logger)
    {
        _authApi = authApi;
        _session = session;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<AuthOutcome> LoginAsync(string email, string password, CancellationToken cancellationToken)
    {
        LoginLocalUserRequest request = new(email, password, _options.ProjectId);
        ILoginLocalUserApiResponse response = await _authApi.LoginLocalUserAsync(request, cancellationToken);

        if (!response.TryOk(out LoginLocalUser200Response? body) || body?.Token is not { Length: > 0 } token)
        {
            return AuthOutcome.Failure(MudbaseApiException.From(response).Message);
        }

        _session.SetTokens(token, body.RefreshToken);
        await RefreshSessionAsync(cancellationToken);
        return AuthOutcome.Success();
    }

    /// <summary>
    /// Fetches the full, authoritative session user (including customRole, which the login
    /// response's typed model doesn't expose) and caches it in session state. Call after every
    /// token change (login, refresh) - mirrors refreshSession() in ../../web/src/lib/mudbase-provider.tsx.
    /// </summary>
    public async Task RefreshSessionAsync(CancellationToken cancellationToken)
    {
        if (!_session.HasToken)
        {
            _session.ClearUser();
            return;
        }

        IGetLocalSessionApiResponse response = await _authApi.GetLocalSessionAsync(_options.ProjectId, cancellationToken);

        if (!response.TryOk(out GetLocalSession200Response? body) || body?.User is not JsonElement userElement)
        {
            _session.ClearToken();
            _session.ClearUser();
            return;
        }

        MudbaseSessionUser? user = JsonSerializer.Deserialize<MudbaseSessionUser>(userElement.GetRawText(), MudbaseJson.Options);
        _session.SetUser(user ?? new MudbaseSessionUser());
    }

    public async Task LogoutAsync(CancellationToken cancellationToken)
    {
        if (_session.HasToken)
        {
            try
            {
                await _authApi.LogoutLocalUserAsync(cancellationToken);
            }
            catch (HttpRequestException ex)
            {
                // Best-effort: the browser's session is cleared regardless so the user is signed
                // out locally even if Mudbase couldn't be reached to revoke server-side.
                _logger.LogWarning(ex, "Mudbase logout call failed; clearing local session anyway");
            }
        }

        _session.ClearToken();
        _session.ClearUser();
    }
}
