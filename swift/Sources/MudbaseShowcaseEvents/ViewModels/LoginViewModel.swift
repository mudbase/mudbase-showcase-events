import Foundation

/// Mirrors `LoginForm.tsx` + `useAuth.ts`'s `login`.
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""

    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let sessionStore: SessionStore

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    var canSubmit: Bool { !isSubmitting && !email.isEmpty && !password.isEmpty }

    func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        switch await sessionStore.login(email: email, password: password) {
        case .success:
            break
        case .failure(let error):
            if error.code == "EMAIL_VERIFICATION_REQUIRED" {
                errorMessage = "Please verify your email first — check your inbox for the verification link, then sign in."
            } else {
                errorMessage = error.message
            }
        }
    }
}
