package mbase

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	mudbase "github.com/mudbase/mudbase-sdk/go"
)

// AuthUser is this app's normalized view of a Mudbase end-user, decoded straight from the raw
// JSON response body of every auth call.
//
// Known SDK gap (same one documented in the social/kanban ports): the vendored mudbase-sdk/go's
// generated response models for LoginLocalUser, GetCurrentSession, and RefreshToken omit
// `customRole` entirely, even though the live API returns it (confirmed against the reference web
// app's working use of `session.user.customRole` in web/src/lib/mudbase.ts, and against this app's
// own live smoke test - see plan/build-plan.md). Rather than losing it, every auth call below still
// executes through the real generated SDK method (for request construction, header/auth wiring,
// and error handling), then re-decodes the *http.Response body it returns into this struct - the
// generated client preserves that raw body via io.NopCloser(bytes.NewBuffer(...)) after its own
// typed decode, so this is a safe, side-effect-free second read, not a duplicate request.
type AuthUser struct {
	ID         string
	Email      string
	FirstName  string
	LastName   string
	Role       string
	CustomRole string // "organizer" | "attendee" - this app's Multi-Role signup slugs.
}

// AuthResult is the normalized shape of every auth response this app cares about.
type AuthResult struct {
	Token               string
	RefreshToken        string
	ExpiresIn           int32
	RequireVerification bool
	User                AuthUser
}

// authWireUser is the raw wire shape of the `user` object on every auth response, capturing the
// field the generated Login/Session/Refresh models omit alongside the ones they do carry.
type authWireUser struct {
	ID         string `json:"id"`
	Email      string `json:"email"`
	FirstName  string `json:"firstName"`
	LastName   string `json:"lastName"`
	Role       string `json:"role"`
	CustomRole string `json:"customRole"`
}

// authWireResponse is the raw wire shape shared by LoginLocalUser, GetCurrentSession, and
// RegisterWithRole.
type authWireResponse struct {
	Message             string       `json:"message"`
	RequireVerification bool         `json:"requireVerification"`
	Token               string       `json:"token"`
	RefreshToken        string       `json:"refreshToken"`
	ExpiresIn           int32        `json:"expiresIn"`
	User                authWireUser `json:"user"`
}

func decodeAuthBody(body []byte) (AuthResult, error) {
	var wire authWireResponse
	if err := json.Unmarshal(body, &wire); err != nil {
		return AuthResult{}, fmt.Errorf("mbase: decoding auth response body: %w", err)
	}
	return AuthResult{
		Token:               wire.Token,
		RefreshToken:        wire.RefreshToken,
		ExpiresIn:           wire.ExpiresIn,
		RequireVerification: wire.RequireVerification,
		User: AuthUser{
			ID:         wire.User.ID,
			Email:      wire.User.Email,
			FirstName:  wire.User.FirstName,
			LastName:   wire.User.LastName,
			Role:       wire.User.Role,
			CustomRole: wire.User.CustomRole,
		},
	}, nil
}

// readPreservedBody reads the response body the generated SDK preserves via
// io.NopCloser(bytes.NewBuffer(...)) after its own decode, without disturbing anything the caller
// still wants to read (rare, but resets Body afterward so it stays safe to consume again).
func readPreservedBody(resp *http.Response) ([]byte, error) {
	if resp == nil || resp.Body == nil {
		return nil, fmt.Errorf("mbase: no response body to read")
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("mbase: reading response body: %w", err)
	}
	resp.Body.Close()
	resp.Body = io.NopCloser(bytes.NewBuffer(body))
	return body, nil
}

// Login authenticates one of the two pre-provisioned demo accounts (organizer/attendee - see
// plan/build-plan.md) or a self-registered account via email/password. There is no anonymous
// session in this app: every role must sign in because every collection read on this backend
// requires *some* authentication, and this project has no public role configured (verified live).
func (c *Client) Login(ctx context.Context, email, password string) (AuthResult, error) {
	req := mudbase.NewLoginLocalUserRequest(email, password)
	req.SetProjectId(c.cfg.ProjectID)

	_, httpResp, err := c.SDK.AuthenticationAPI.LoginLocalUser(ctx).
		LoginLocalUserRequest(*req).
		Execute()
	if err != nil {
		return AuthResult{}, wrapAPIError("mbase: logging in", err)
	}

	body, err := readPreservedBody(httpResp)
	if err != nil {
		return AuthResult{}, err
	}
	return decodeAuthBody(body)
}

// Register signs up a brand-new account under the given Multi-Role signup slug ("organizer" or
// "attendee") via the public RegisterWithRole endpoint. Included for parity with the reference web
// app's nice-to-have /register page - the two shared demo accounts remain the primary path for the
// live smoke test, since registration is rate-limited and shared across concurrently-worked
// sibling showcase projects. When the project requires email verification, RequireVerification is
// true and no token is issued - the caller must not attempt to establish a session in that case.
func (c *Client) Register(ctx context.Context, role, email, password, firstName, lastName string) (AuthResult, error) {
	req := mudbase.NewRegisterWithRoleRequest(email, password, firstName, lastName, c.cfg.ProjectID, true)

	_, httpResp, err := c.SDK.MultiRoleFeatureAPI.RegisterWithRole(ctx, role).
		RegisterWithRoleRequest(*req).
		Execute()
	if err != nil {
		return AuthResult{}, wrapAPIError("mbase: registering", err)
	}

	body, err := readPreservedBody(httpResp)
	if err != nil {
		return AuthResult{}, err
	}
	return decodeAuthBody(body)
}

// Logout revokes the current session's token server-side. Mudbase's `LogoutLocalUser` needs no
// request body, only the bearer token attached via authedContext.
func (c *Client) Logout(ctx context.Context, token string) error {
	_, _, err := c.SDK.AuthenticationAPI.LogoutLocalUser(authedContext(ctx, token)).Execute()
	if err != nil {
		return wrapAPIError("mbase: logging out", err)
	}
	return nil
}

// Refresh exchanges refreshToken for a new access token + refresh token pair. The previous refresh
// token is invalidated by rotation the moment this succeeds - confirmed against
// mudbase-sdk/go/api_authentication.go's RefreshToken doc comment ("the previous refresh token is
// invalidated ... if the same refresh token is used again, the session is revoked"), so callers
// must persist both returned values, not just the new access token. No bearer token is attached to
// this call; POST /api/auth/refresh authenticates purely via the refresh token in the request
// body. The response carries no `user` object, so the returned AuthResult's User field is left
// zero-valued - callers refreshing an existing session should keep whatever user snapshot they
// already have and only replace the token pair (see internal/server/middleware.go's
// tokenRefresher).
func (c *Client) Refresh(ctx context.Context, refreshToken string) (AuthResult, error) {
	req := mudbase.NewRefreshTokenRequest(refreshToken)

	resp, _, err := c.SDK.AuthenticationAPI.RefreshToken(ctx).
		RefreshTokenRequest(*req).
		Execute()
	if err != nil {
		return AuthResult{}, wrapAPIError("mbase: refreshing access token", err)
	}

	return AuthResult{
		Token:        resp.GetToken(),
		RefreshToken: resp.GetRefreshToken(),
		ExpiresIn:    resp.GetExpiresIn(),
	}, nil
}
