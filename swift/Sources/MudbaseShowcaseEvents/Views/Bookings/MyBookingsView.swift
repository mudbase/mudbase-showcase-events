import SwiftUI

/// Mirrors `BookingList.tsx` — the signed-in attendee's own bookings across every event.
struct MyBookingsView: View {
    let config: AppConfig
    let currentUser: AppUser
    @StateObject private var viewModel: MyBookingsViewModel

    init(config: AppConfig, currentUser: AppUser) {
        self.config = config
        self.currentUser = currentUser
        _viewModel = StateObject(wrappedValue: MyBookingsViewModel(config: config, currentUser: currentUser))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView()
            } else if viewModel.bookings.isEmpty {
                EmptyStateView(systemImage: "ticket", message: "You haven't booked any events yet.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.bookings) { booking in
                            BookingCardView(
                                booking: booking,
                                event: viewModel.eventsById[booking.eventId],
                                canCancel: viewModel.canCancel(booking),
                                isCancelling: viewModel.cancellingBookingId == booking.id,
                                onCancel: { Task { await viewModel.cancel(booking) } }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("My bookings")
        .task { await viewModel.load() }
    }
}
