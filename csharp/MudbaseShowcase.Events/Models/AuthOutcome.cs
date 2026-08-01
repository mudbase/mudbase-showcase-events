namespace MudbaseShowcase.Events.Models;

/// <summary>Result of a login attempt against Mudbase, for display in a Razor Page without throwing on expected failures (bad credentials, 403, etc).</summary>
public sealed class AuthOutcome
{
    public bool Succeeded { get; private init; }
    public string? ErrorMessage { get; private init; }

    public static AuthOutcome Success() => new() { Succeeded = true };

    public static AuthOutcome Failure(string message) => new() { Succeeded = false, ErrorMessage = message };
}
