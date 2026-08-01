import SwiftUI

/// Mirrors `EventForm.tsx` — handles both "New event" and "Edit event".
struct EventFormView: View {
    @StateObject private var viewModel: EventFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(config: AppConfig, existingEvent: EventItem?, currentUser: AppUser) {
        _viewModel = StateObject(wrappedValue: EventFormViewModel(
            config: config,
            existingEvent: existingEvent,
            actorId: currentUser.id,
            actorName: currentUser.displayName
        ))
    }

    var body: some View {
        Form {
            if let errorMessage = viewModel.errorMessage {
                Section { InlineBanner(message: errorMessage) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Details") {
                TextField("Title", text: $viewModel.draft.title)
                TextField("Description", text: $viewModel.draft.description, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Location", text: $viewModel.draft.location)
            }

            Section("Date & capacity") {
                DatePicker("Date & time", selection: $viewModel.draft.startsAt)
                Stepper(value: $viewModel.draft.capacity, in: 1...100_000) {
                    LabeledContent("Capacity") {
                        Text("\(viewModel.draft.capacity)")
                    }
                }
                Text("Bookings beyond capacity are automatically waitlisted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task {
                        await viewModel.save()
                        if viewModel.didSave { dismiss() }
                    }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text(viewModel.isEditing ? "Save changes" : "Create event")
                    }
                }
                .disabled(viewModel.isSubmitting)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit event" : "New event")
        .inlineNavigationTitle()
    }
}
