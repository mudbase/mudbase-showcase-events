package models

// BookingStatus enumerates every value this app writes to `bookings.status`. The real Mudbase
// platform bug that once blanket-blocked writes to any field literally named `status` (see
// plan/build-plan.md "Note on a Real Platform Bug") is fixed server-side (mudbase-server commit
// 251db188) - this field is written directly, no workaround needed.
type BookingStatus string

const (
	StatusConfirmed  BookingStatus = "confirmed"
	StatusWaitlisted BookingStatus = "waitlisted"
	StatusCancelled  BookingStatus = "cancelled"
	StatusCheckedIn  BookingStatus = "checked_in"
)

// Booking mirrors the `bookings` Mudbase collection schema.
type Booking struct {
	ID        string        `json:"_id"`
	CreatedAt string        `json:"createdAt"`
	UpdatedAt string        `json:"updatedAt"`
	EventID   string        `json:"eventId"`
	UserID    string        `json:"userId"`
	UserName  string        `json:"userName"`
	Status    BookingStatus `json:"status"`
	QRToken   string        `json:"qrToken"`
}

// IsLive reports whether the booking still holds a place (confirmed or waitlisted) - i.e. every
// status the capacity-reconciliation pass in internal/store/capacity.go considers, as opposed to
// cancelled (permanently out) or checked_in (already seated, excluded from reconciliation per
// plan/build-plan.md "Capacity-Race Handling Approach").
func (b Booking) IsLive() bool {
	return b.Status == StatusConfirmed || b.Status == StatusWaitlisted
}
