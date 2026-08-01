namespace MudbaseShowcase.Events.Services;

/// <summary>Named HttpClient identifiers used outside the Mudbase SDK's own generated typed clients.</summary>
public static class HttpClientNames
{
    /// <summary>Direct, handler-free HTTP access to the Mudbase base URL - used by TokenRefreshHandler's POST /api/auth/refresh call so a refresh can never recurse through its own 401-retry pipeline.</summary>
    public const string MudbaseRaw = "MudbaseRaw";
}
