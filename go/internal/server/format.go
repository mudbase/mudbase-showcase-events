package server

import (
	"encoding/base64"
	"fmt"
	"strings"
	"time"

	qrcode "github.com/skip2/go-qrcode"
)

// formatDateTime parses an RFC3339 timestamp (as returned by Mudbase's startsAt/createdAt fields)
// and renders it in a medium, readable form. Malformed or empty input renders as "-" rather than
// panicking or leaking a raw parse error into the page. Ported from the reference web app's
// src/lib/utils.ts (formatDateTime).
func formatDateTime(iso string) string {
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		return "-"
	}
	return t.Local().Format("Jan 2, 2006, 3:04 PM")
}

// toDateTimeLocalValue converts an ISO date-time string to the value a
// `<input type="datetime-local">` expects (local time, no timezone/seconds), for pre-filling the
// edit-event form. Ported from the reference web app's src/lib/utils.ts
// (toDateTimeLocalValue).
func toDateTimeLocalValue(iso string) string {
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		return ""
	}
	return t.Local().Format("2006-01-02T15:04")
}

// datetimeLocalToISO converts a `<input type="datetime-local">` submitted value ("2006-01-02T15:04")
// back into an RFC3339 string in the server's local zone, the wire shape Mudbase's `startsAt` field
// expects. Empty or malformed input returns "" so the caller can reject it as a validation error
// rather than writing a garbage timestamp.
func datetimeLocalToISO(value string) string {
	t, err := time.ParseInLocation("2006-01-02T15:04", value, time.Local)
	if err != nil {
		return ""
	}
	return t.Format(time.RFC3339)
}

// initials renders up to two uppercase letters from name for the avatar-circle fallback this app
// uses wherever a real profile photo would go - there is no `users` collection, so a name is just
// the typed organizerName/userName. Ported from the reference web app's src/lib/utils.ts
// (initials).
func initials(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return "?"
	}
	fields := strings.Fields(name)
	if len(fields) == 1 {
		runes := []rune(fields[0])
		if len(runes) == 1 {
			return strings.ToUpper(string(runes[0]))
		}
		return strings.ToUpper(string(runes[:2]))
	}
	first := []rune(fields[0])[0]
	last := []rune(fields[len(fields)-1])[0]
	return strings.ToUpper(string(first) + string(last))
}

// qrDataURI renders token as a scannable QR code PNG, inlined as a base64 data URI so the
// check-in ticket image needs no server round-trip and no client-side JavaScript library - the
// server-rendered equivalent of the reference web app's `<QRCodeSVG>` (qrcode.react). Returns ""
// on encode failure so a broken booking row never crashes the whole bookings page - the raw
// qrToken text is always rendered alongside it as a manual-entry fallback regardless.
func qrDataURI(token string) string {
	png, err := qrcode.Encode(token, qrcode.Medium, 220)
	if err != nil {
		return ""
	}
	return fmt.Sprintf("data:image/png;base64,%s", base64.StdEncoding.EncodeToString(png))
}
