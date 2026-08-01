package store

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
)

// generateQRToken produces a random, unguessable single-use check-in code: 16 random bytes
// (128 bits of entropy) hex-encoded to a 32-character string - the same shape as the reference web
// app's generateQrToken (src/lib/utils.ts), which uses crypto.randomUUID() with its dashes
// stripped (122 bits of entropy from a v4 UUID). Not a security credential in the cryptographic
// sense (this is a demo ticketing app, not a payments system) - collision resistance at this
// entropy is more than sufficient for a QR check-in token.
func generateQRToken() (string, error) {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("store: generating qr token: %w", err)
	}
	return hex.EncodeToString(buf), nil
}
