import SwiftUI

/// Mirrors `EventCard.tsx` — each card independently fetches its own live confirmed count (see
/// `EventCardViewModel`), matching `useConfirmedCount(event._id)` being called from the card
/// component itself rather than the parent list.
struct EventCardView: View {
    let event: EventItem
    @StateObject private var viewModel: EventCardViewModel

    init(config: AppConfig, event: EventItem) {
        self.event = event
        _viewModel = StateObject(wrappedValue: EventCardViewModel(config: config, eventId: event.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Hosted by \(event.organizerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CapacityBadgeView(confirmed: viewModel.confirmedCount, capacity: event.capacity, isLoading: viewModel.isLoading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(Formatting.dateTime(event.startsAt), systemImage: "calendar")
                Label(event.location, systemImage: "mappin.and.ellipse")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .task { await viewModel.load() }
    }
}
