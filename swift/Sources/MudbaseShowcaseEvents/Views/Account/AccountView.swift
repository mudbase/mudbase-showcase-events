import SwiftUI

struct AccountView: View {
    let user: AppUser
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Name", value: user.displayName)
                LabeledContent("Email", value: user.email)
                LabeledContent("Role", value: user.isOrganizer ? "Organizer" : "Attendee")
            }

            Section {
                Button("Sign out", role: .destructive) {
                    Task { await sessionStore.logout() }
                }
            }
        }
        .navigationTitle("Account")
    }
}
