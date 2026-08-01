package dev.mudbase.showcase.events.support;

import java.util.UUID;

/**
 * A random, unguessable single-use check-in code for a new booking. Not a security credential in
 * the cryptographic sense (this is a demo ticketing app, not a payments system) - collision
 * resistance against a random UUID's 122 bits of entropy is more than sufficient for a QR
 * check-in token. Mirrors the reference web app's `generateQrToken()` (../web/src/lib/utils.ts):
 * a random UUID with its hyphens stripped.
 */
public final class QrTokenGenerator {

  private QrTokenGenerator() {}

  public static String generate() {
    return UUID.randomUUID().toString().replace("-", "");
  }
}
