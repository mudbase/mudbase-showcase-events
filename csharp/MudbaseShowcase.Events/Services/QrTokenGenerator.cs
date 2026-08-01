namespace MudbaseShowcase.Events.Services;

/// <summary>
/// A random, unguessable single-use check-in code. Not a security credential in the
/// cryptographic sense (this is a demo ticketing app, not a payments system) - direct port of
/// ../../web/src/lib/utils.ts's `generateQrToken` (`crypto.randomUUID().replace(/-/g, "")`):
/// `Guid.NewGuid().ToString("N")` produces the identical shape - 32 lowercase hex characters, no
/// dashes - from the same 122 bits of random UUID entropy.
/// </summary>
public static class QrTokenGenerator
{
    public static string Generate() => Guid.NewGuid().ToString("N");
}
