package mbase

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	mudbase "github.com/mudbase/mudbase-sdk/go"
)

// wireError is the common {"error": "...", "message": "..."} shape Mudbase's REST API returns on
// failure - the SDK's GenericOpenAPIError body uses it.
type wireError struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

// FriendlyMessage extracts a human-readable message from an error returned by this package. The
// generated SDK client wraps every non-2xx response in a *mudbase.GenericOpenAPIError carrying the
// raw response body (see mudbase-sdk/go/client.go); this unwraps that body's {error} or {message}
// field instead of surfacing the generic "400 Bad Request"-style Error() string.
func FriendlyMessage(err error) string {
	if err == nil {
		return ""
	}

	var apiErr *mudbase.GenericOpenAPIError
	if errors.As(err, &apiErr) {
		var wire wireError
		if jsonErr := json.Unmarshal(apiErr.Body(), &wire); jsonErr == nil {
			if wire.Error != "" {
				return wire.Error
			}
			if wire.Message != "" {
				return wire.Message
			}
		}
	}
	return err.Error()
}

// wrapAPIError produces a consistently-formatted, %w-wrapped error carrying the friendly message
// as context, per this project's "every error wrapped with fmt.Errorf" rule.
func wrapAPIError(action string, err error) error {
	return fmt.Errorf("%s: %s: %w", action, FriendlyMessage(err), err)
}

// IsUnauthorized reports whether err represents an HTTP 401 response from the Mudbase API - an
// expired or invalid access token, as opposed to any other 4xx/5xx failure a token refresh cannot
// fix. The generated SDK client records the response's Status string (e.g. "401 Unauthorized") as
// GenericOpenAPIError's error field (see mudbase-sdk/go/client.go's callAPI), so that's what this
// checks against rather than a parsed status code the SDK doesn't expose.
func IsUnauthorized(err error) bool {
	if err == nil {
		return false
	}
	var apiErr *mudbase.GenericOpenAPIError
	if errors.As(err, &apiErr) {
		return strings.HasPrefix(apiErr.Error(), "401")
	}
	return false
}

// IsForbidden reports whether err represents an HTTP 403 response - Mudbase's own collection
// permissions rejecting a role that lacks the required action (e.g. an `attendee` attempting an
// organizer-only write). This is the real, server-side RBAC enforcement boundary this app's own
// role checks (internal/rbac) are only a UX mirror of - see plan/build-plan.md "RBAC Matrix".
func IsForbidden(err error) bool {
	if err == nil {
		return false
	}
	var apiErr *mudbase.GenericOpenAPIError
	if errors.As(err, &apiErr) {
		return strings.HasPrefix(apiErr.Error(), "403")
	}
	return false
}
