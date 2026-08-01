import SwiftUI

/// Mirrors `OrganizerActions.tsx` — Edit/Check-in navigation plus a two-step (confirm-then-delete)
/// delete action. Only ever shown when `event.organizerId == currentUser.id` (see
/// `EventDetailView`), matching the web app's `isOwner` gate.
struct OrganizerActionsView: View {
    let config: AppConfig
    let event: EventItem
    let currentUser: AppUser
    @StateObject private var viewModel: OrganizerActionsViewModel
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(config: AppConfig, event: EventItem, currentUser: AppUser) {
        self.config = config
        self.event = event
        self.currentUser = currentUser
        _viewModel = StateObject(wrappedValue: OrganizerActionsViewModel(config: config, eventId: event.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Organizer")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                NavigationLink {
                    EventFormView(config: config, existingEvent: event, currentUser: currentUser)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    CheckInView(config: config, event: event)
                } label: {
                    Label("Check-in", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.bordered)
            }

            if isConfirmingDelete {
                HStack(spacing: 10) {
                    Text("Delete this event permanently?")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        Task {
                            await viewModel.delete()
                            if viewModel.didDelete { dismiss() }
                        }
                    } label: {
                        if viewModel.isDeleting {
                            ProgressView()
                        } else {
                            Text("Confirm delete")
                        }
                    }
                    Button("Cancel") { isConfirmingDelete = false }
                }
            } else {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
