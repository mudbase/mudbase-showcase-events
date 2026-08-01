import SwiftUI

/// Mirrors `BookingCard.tsx` — the QR code shown here is what an organizer scans/types at
/// `CheckInView`.
struct BookingCardView: View {
    let booking: Booking
    let event: EventItem?
    let canCancel: Bool
    let isCancelling: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event?.title ?? "Event unavailable")
                        .font(.headline)
                    if let event {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(Formatting.dateTime(event.startsAt), systemImage: "calendar")
                            Label(event.location, systemImage: "mappin.and.ellipse")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusBadge
            }

            HStack(alignment: .center) {
                if booking.status != .cancelled {
                    HStack(spacing: 10) {
                        QRCodeView(text: booking.qrToken, size: 64)
                            .padding(6)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        Text(booking.qrToken)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("This booking was cancelled.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if canCancel {
                    Button(role: .destructive, action: onCancel) {
                        if isCancelling {
                            ProgressView()
                        } else {
                            Text("Cancel")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCancelling)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch booking.status {
            case .confirmed: return ("Confirmed", .green)
            case .waitlisted: return ("Waitlisted", .orange)
            case .checkedIn: return ("Checked in", .blue)
            case .cancelled: return ("Cancelled", .secondary)
            }
        }()
        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }
}
