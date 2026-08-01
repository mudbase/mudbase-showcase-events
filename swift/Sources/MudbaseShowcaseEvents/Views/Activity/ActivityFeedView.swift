import SwiftUI

/// Mirrors `ActivityFeed.tsx` — reverse-chronological activity feed for one event.
struct ActivityFeedView: View {
    @StateObject private var viewModel: ActivityFeedViewModel

    init(config: AppConfig, eventId: String) {
        _viewModel = StateObject(wrappedValue: ActivityFeedViewModel(config: config, eventId: eventId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Activity", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))

            if viewModel.isLoading {
                Text("Loading activity…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.entries.isEmpty {
                Text("No activity yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.entries) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            (Text(entry.actorName).fontWeight(.semibold) + Text(" \(entry.action.label)").foregroundColor(.secondary))
                                .font(.footnote)
                            Spacer()
                            Text(entry.createdAt.map(Formatting.relativeTime) ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }
}
