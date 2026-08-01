import SwiftUI

/// Mirrors `BookButton.tsx`. The "sign in to book" branch from the web version doesn't apply here —
/// this app requires login before any screen that could show this button is reachable at all (see
/// `RootView`) — so this only ever handles the signed-in cases: own event (hidden), an existing
/// active booking (status badge), or the book affordance itself.
struct BookButtonView: View {
    let config: AppConfig
    let currentUser: AppUser
    @ObservedObject var viewModel: EventDetailViewModel

    var body: some View {
        Group {
            if viewModel.isOwnEvent {
                EmptyView()
            } else if viewModel.isLoadingBooking {
                Button("Checking your booking…") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            } else if let active = viewModel.activeBooking {
                HStack(spacing: 10) {
                    statusBadge(for: active.status)
                    NavigationLink("View my bookings") {
                        MyBookingsView(config: config, currentUser: currentUser)
                    }
                    .font(.footnote)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        Task { await viewModel.book() }
                    } label: {
                        if viewModel.isBooking {
                            ProgressView()
                        } else {
                            Text("Book this event")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isBooking)

                    if let feedback = viewModel.bookingFeedback {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func statusBadge(for status: BookingStatus) -> some View {
        let (label, color) = Self.statusBadgeContent(for: status)
        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }

    private static func statusBadgeContent(for status: BookingStatus) -> (label: String, color: Color) {
        switch status {
        case .confirmed: return ("You're booked", .green)
        case .waitlisted: return ("You're on the waitlist", .orange)
        case .checkedIn: return ("You're checked in", .blue)
        case .cancelled: return ("Booking cancelled", .secondary)
        }
    }
}
