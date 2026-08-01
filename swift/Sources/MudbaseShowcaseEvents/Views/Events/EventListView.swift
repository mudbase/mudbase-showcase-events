import SwiftUI

/// Mirrors `EventList.tsx` + `page.tsx` — paginated (10/page), soonest-first event list. Organizers
/// get a "New event" toolbar button; attendees don't (mirroring the web app's organizer-only create
/// affordance).
struct EventListView: View {
    let config: AppConfig
    let currentUser: AppUser
    @StateObject private var viewModel: EventListViewModel

    init(config: AppConfig, currentUser: AppUser) {
        self.config = config
        self.currentUser = currentUser
        _viewModel = StateObject(wrappedValue: EventListViewModel(config: config))
    }

    var body: some View {
        content
            .navigationTitle("Events")
            .toolbar {
                if currentUser.isOrganizer {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            EventFormView(config: config, existingEvent: nil, currentUser: currentUser)
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            LoadingView()
        } else if let errorMessage = viewModel.errorMessage {
            InlineErrorView(message: errorMessage) { Task { await viewModel.load() } }
        } else if viewModel.events.isEmpty {
            EmptyStateView(systemImage: "calendar.badge.exclamationmark", message: "No events yet.")
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.events) { event in
                        NavigationLink {
                            EventDetailView(config: config, eventId: event.id, currentUser: currentUser)
                        } label: {
                            EventCardView(config: config, event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                if viewModel.totalPages > 1 {
                    pagingControls
                        .padding(.horizontal)
                        .padding(.bottom)
                }
            }
        }
    }

    private var pagingControls: some View {
        HStack {
            Button {
                Task { await viewModel.previousPage() }
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(viewModel.page <= 1)

            Spacer()
            Text("Page \(viewModel.page) of \(viewModel.totalPages)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                Task { await viewModel.nextPage() }
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(!viewModel.hasMore)
        }
    }
}
