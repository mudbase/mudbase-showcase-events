import SwiftUI

/// Mirrors `CheckInForm.tsx` — manual paste/type entry is the primary, always-available path on
/// every platform (matching the web app exactly); a camera "Scan QR" option is additionally offered
/// on iOS (see `QRScannerView`, compiled only on iOS — not present in the web reference at all,
/// added here since a native app can reasonably use the device camera).
struct CheckInView: View {
    let event: EventItem
    @StateObject private var viewModel: CheckInViewModel
    #if os(iOS)
    @State private var isShowingScanner = false
    #endif

    init(config: AppConfig, event: EventItem) {
        self.event = event
        _viewModel = StateObject(wrappedValue: CheckInViewModel(config: config, eventId: event.id))
    }

    var body: some View {
        Form {
            Section {
                TextField("Scanned / pasted code", text: $viewModel.qrToken)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                HStack {
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Check in")
                        }
                    }
                    .disabled(!viewModel.canSubmit)

                    #if os(iOS)
                    Spacer()
                    Button {
                        isShowingScanner = true
                    } label: {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                    }
                    #endif
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let result = viewModel.result {
                Section { resultBanner(for: result) }
            }
        }
        .navigationTitle("Check in — \(event.title)")
        .inlineNavigationTitle()
        #if os(iOS)
        .sheet(isPresented: $isShowingScanner) {
            QRScannerView { token in
                isShowingScanner = false
                Task { await viewModel.submit(scannedToken: token) }
            }
        }
        #endif
    }

    @ViewBuilder
    private func resultBanner(for result: BookingsService.CheckInOutcome) -> some View {
        let content = Self.bannerContent(for: result)
        HStack(spacing: 10) {
            Image(systemName: content.icon)
                .foregroundStyle(content.tint)
            Text(content.message)
        }
        .font(.subheadline)
    }

    private static func bannerContent(for result: BookingsService.CheckInOutcome) -> (icon: String, tint: Color, message: String) {
        switch result {
        case .checkedIn(let booking):
            return ("checkmark.circle.fill", .green, "\(booking.userName) is checked in.")
        case .alreadyCheckedIn(let booking):
            return ("exclamationmark.triangle.fill", .orange, "\(booking.userName) was already checked in.")
        case .waitlisted(let booking):
            return ("exclamationmark.triangle.fill", .orange, "\(booking.userName) is on the waitlist, not confirmed — cannot check in.")
        case .cancelled(let booking):
            return ("xmark.circle.fill", .red, "\(booking.userName)'s booking was cancelled.")
        case .notFound:
            return ("xmark.circle.fill", .red, "No booking found for this code at this event.")
        }
    }
}
