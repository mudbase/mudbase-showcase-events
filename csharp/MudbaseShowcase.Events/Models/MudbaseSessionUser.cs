using System.Text.Json.Serialization;

namespace MudbaseShowcase.Events.Models;

/// <summary>
/// The authenticated user info this app cares about, parsed from Mudbase's session/user payload
/// (which the generated SDK types loosely as `Object` - see
/// <see cref="MudbaseShowcase.Events.Services.MudbaseAuthService"/>). Mirrors
/// ../../web/src/lib/mudbase.ts's UserObject. This app has no anonymous/guest session at all -
/// every request either carries a real signed-in user or gets redirected to /Login by
/// RequireMudbaseSessionMiddleware, so there is no IsAnonymous flag here.
/// </summary>
public sealed class MudbaseSessionUser
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("email")]
    public string Email { get; set; } = string.Empty;

    [JsonPropertyName("firstName")]
    public string FirstName { get; set; } = string.Empty;

    [JsonPropertyName("lastName")]
    public string LastName { get; set; } = string.Empty;

    [JsonPropertyName("role")]
    public string? Role { get; set; }

    /// <summary>Mudbase Multi-Role customRole - "organizer" or "attendee" for this project. See Services/Rbac.cs.</summary>
    [JsonPropertyName("customRole")]
    public string? CustomRole { get; set; }

    [JsonPropertyName("emailVerified")]
    public bool EmailVerified { get; set; }

    /// <summary>True once a real session user has been loaded (a non-empty id). Used defensively in case a token exists but RefreshSessionAsync could not resolve a user.</summary>
    public bool IsSignedIn => !string.IsNullOrEmpty(Id);

    /// <summary>"First Last", trimmed - used as the denormalized organizerName/userName/actorName written to every collection row this user creates.</summary>
    public string DisplayName => $"{FirstName} {LastName}".Trim();
}
