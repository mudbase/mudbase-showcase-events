import Foundation

/// Mirrors `CheckInForm.tsx` + `useCheckIn` — a single text field for a pasted/typed/scanned
/// `qrToken`, submitted against one event.
@MainActor
final class CheckInViewModel: ObservableObject {
    @Published var qrToken = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var result: BookingsService.CheckInOutcome?
    @Published private(set) var errorMessage: String?

    private let service: BookingsService
    private let eventId: String

    init(config: AppConfig, eventId: String) {
        service = BookingsService(config: config)
        self.eventId = eventId
    }

    var canSubmit: Bool { !isSubmitting && !qrToken.trimmingCharacters(in: .whitespaces).isEmpty }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            result = try await service.checkIn(eventId: eventId, qrToken: qrToken)
            qrToken = ""
        } catch {
            errorMessage = MudbaseAPIError.map(error).message
        }
    }

    /// Called by the camera scanner (`QRScannerView`, iOS only) once it decodes a QR payload —
    /// fills the field and submits immediately, mirroring how pasting a code and tapping "Check in"
    /// would behave.
    func submit(scannedToken: String) async {
        qrToken = scannedToken
        await submit()
    }
}
