<?php

declare(strict_types=1);

namespace App\Support;

/**
 * A PHP port of the reference app's `pseudoObjectId()` (src/lib/utils.ts), using the same djb2
 * string hash — carried into this app for architectural parity with the sibling PHP ports
 * (kanban's `assigneeId`, social's/ecommerce's own free-typed-name cases), where an `...Id`-suffixed
 * field must satisfy the platform's real-ObjectId-format query-sanitizer check but has no backing
 * document to source a real id from.
 *
 * This specific app's data model (see plan/build-plan.md) has no such field: `organizerId` and
 * `userId` are always the signed-in session user's real Mudbase id, and `eventId` is always a
 * fetched event document's real `_id` — there is no free-typed name anywhere that needs a
 * fabricated id. This class is therefore not called from any controller in this app; it is kept,
 * fully implemented and unit-verified against the reference algorithm, purely so a future
 * free-typed-identity feature (e.g. a walk-in guest registered by name only) has a ready,
 * consistent tool rather than each showcase port re-deriving its own hash scheme.
 */
final class PseudoId
{
    private const UINT32_MODULUS = 4294967296; // 2^32
    private const INT32_MAX = 2147483648; // 2^31

    public static function pseudoObjectId(string $seed): string
    {
        $trimmed = strtolower(trim($seed));
        $hex = '';
        $round = 0;
        while (strlen($hex) < 24) {
            $hex .= str_pad(dechex(self::djb2("{$trimmed}:{$round}")), 8, '0', STR_PAD_LEFT);
            $round++;
        }
        return substr($hex, 0, 24);
    }

    /** Mirrors the reference app's `djb2()`, including its JS Int32 bitwise-op wraparound. */
    private static function djb2(string $str): int
    {
        $hash = 5381;
        $length = strlen($str);
        for ($i = 0; $i < $length; $i++) {
            $hash = self::toInt32($hash * 33) ^ ord($str[$i]);
        }
        return $hash < 0 ? $hash + self::UINT32_MODULUS : $hash;
    }

    /** Wraps an arbitrary integer into JS's signed Int32 range, the same way `x | 0` / bitwise ops would. */
    private static function toInt32(int $n): int
    {
        $n %= self::UINT32_MODULUS;
        if ($n >= self::INT32_MAX) {
            $n -= self::UINT32_MODULUS;
        } elseif ($n < -self::INT32_MAX) {
            $n += self::UINT32_MODULUS;
        }
        return $n;
    }
}
