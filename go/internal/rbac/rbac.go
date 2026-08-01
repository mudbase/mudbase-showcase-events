// Package rbac defines this app's two role slugs and the operations each one may perform. This is
// a server-side mirror of the reference web app's RBAC matrix (see ../web/plan/build-plan.md),
// used two ways in this app: (1) internal/server/middleware.go's requireOrganizer gates every
// organizer-only write route before a handler ever runs (the "server-side enforcement" the task
// requires, not just hidden template controls), and (2) the page templates read the same
// CanManageEvents/IsOrganizer flags to decide what to render. Neither of those is the real
// security boundary - Mudbase's own collection permissions are (see mbase.IsForbidden) - this
// package exists purely for defense-in-depth and correct UX.
package rbac

// Role slugs this project's Multi-Role auth is configured with.
const (
	RoleOrganizer = "organizer"
	RoleAttendee  = "attendee"
)

// CanManageEvents reports whether role may create/edit/delete events and check attendees in.
// Mudbase's own collection permissions grant this to every organizer account for every event (the
// role has full CRUD on the `events`/`bookings` collections, not a per-document ownership check) -
// this app additionally hides the edit/delete/check-in affordances in the UI unless the viewer is
// that specific event's organizer (organizerId === session user id), a UX-only refinement layered
// on top of the coarser role-level permission (see plan/build-plan.md "RBAC Matrix").
func CanManageEvents(role string) bool {
	return role == RoleOrganizer
}

// IsAttendee reports whether role is the read-events/manage-own-bookings role.
func IsAttendee(role string) bool {
	return role == RoleAttendee
}

// Label renders a role slug for display, "Unknown" for anything unrecognized (including "").
func Label(role string) string {
	switch role {
	case RoleOrganizer:
		return "Organizer"
	case RoleAttendee:
		return "Attendee"
	default:
		return "Unknown"
	}
}

// IsValid reports whether role is one of this app's two known slugs.
func IsValid(role string) bool {
	return role == RoleOrganizer || role == RoleAttendee
}
