import SwiftUI

/// Mirrors `events/[id]/page.tsx` — full event detail: info, capacity badge, book affordance,
/// organizer-only edit/check-in/delete actions, and the activity feed.
struct EventDetailView: View {
    let config: AppConfig
    let currentUser: AppUser
    @StateObject private var viewModel: EventDetailViewModel

    init(config: AppConfig, eventId: String, currentUser: AppUser) {
        self.config = config
        self.currentUser = currentUser
        _viewModel = StateObject(wrappedValue: EventDetailViewModel(config: config, eventId: eventId, currentUser: currentUser))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingView()
            } else if let errorMessage = viewModel.loadErrorMessage, viewModel.event == nil {
                InlineErrorView(message: errorMessage) { Task { await viewModel.load() } }
            } else if let event = viewModel.event {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(for: event)

                        BookButtonView(config: config, currentUser: currentUser, viewModel: viewModel)

                        if viewModel.isOwnEvent {
                            OrganizerActionsView(config: config, event: event, currentUser: currentUser)
                        }

                        Divider()

                        ActivityFeedView(config: config, eventId: event.id)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(viewModel.event?.title ?? "Event")
        .inlineNavigationTitle()
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func header(for event: EventItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(event.title)
                    .font(.title2.bold())
                Spacer()
                CapacityBadgeView(confirmed: viewModel.confirmedCount, capacity: event.capacity, isLoading: viewModel.confirmedCount == nil)
            }
            Text("Hosted by \(event.organizerName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label(Formatting.dateTime(event.startsAt), systemImage: "calendar")
                Label(event.location, systemImage: "mappin.and.ellipse")
                Label("Capacity: \(event.capacity)", systemImage: "person.2")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .padding(.top, 4)
            }
        }
    }
}
