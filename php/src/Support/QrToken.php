<?php

declare(strict_types=1);

namespace App\Support;

/**
 * A random, unguessable single-use check-in code. Not a security credential in the cryptographic
 * sense (this is a demo ticketing app, not a payments system) - collision resistance against
 * 128 bits of `random_bytes` entropy is more than sufficient for a QR check-in token. Mirrors the
 * reference app's `generateQrToken()` (src/lib/utils.ts, `crypto.randomUUID().replace(/-/g, "")`)
 * closely enough for this demo: a 32-hex-character opaque token with comparable entropy.
 */
final class QrToken
{
    public static function generate(): string
    {
        return bin2hex(random_bytes(16));
    }
}
