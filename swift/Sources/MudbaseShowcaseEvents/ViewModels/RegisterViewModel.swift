import Foundation

/// Mirrors `RegisterForm.tsx` + `useAuth.ts`'s `register` — unlike the ecommerce/social Swift
/// ports, this app's register screen has a genuine role picker (`organizer`/`attendee`), matching
/// the reference web form's `ROLE_OPTIONS` toggle exactly.
@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var role: AppRole = .attendee
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published var password = ""
    @Published var agreedToTerms = false

    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let sessionStore: SessionStore

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    private var validationError: String? {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty { return "First name is required" }
        if lastName.trimmingCharacters(in: .whitespaces).isEmpty { return "Last name is required" }
        if !email.contains("@") || email.isEmpty { return "Enter a valid email address" }
        if password.count < 8 { return "Password must be at least 8 characters" }
        if !agreedToTerms { return "You must agree to the Terms of Service and Privacy Policy." }
        return nil
    }

    var canSubmit: Bool { !isSubmitting }

    /// Returns whether the caller landed in a fully signed-in state.
    func submit() async -> Bool {
        if let validationError {
            errorMessage = validationError
            return false
        }
        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        defer { isSubmitting = false }

        switch await sessionStore.register(role: role, email: email, password: password, firstName: firstName, lastName: lastName, agreedToTerms: agreedToTerms) {
        case .signedIn:
            return true
        case .verificationRequired(let message):
            infoMessage = message
            return false
        case .failure(let message):
            errorMessage = message
            return false
        }
    }
}
