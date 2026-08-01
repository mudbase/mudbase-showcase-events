import SwiftUI

/// Both roles see the same three tabs — organizer-only affordances (new event, edit, check-in,
/// delete) are gated inline within `EventListView`/`EventDetailView`, matching the web app's
/// approach of one shared page tree with role-conditional buttons rather than separate navigation
/// per role.
struct MainTabView: View {
    let user: AppUser
    let config: AppConfig

    var body: some View {
        TabView {
            NavigationStack {
                EventListView(config: config, currentUser: user)
            }
            .tabItem { Label("Events", systemImage: "calendar") }

            NavigationStack {
                MyBookingsView(config: config, currentUser: user)
            }
            .tabItem { Label("My bookings", systemImage: "ticket") }

            NavigationStack {
                AccountView(user: user)
            }
            .tabItem { Label("Account", systemImage: "person.circle") }
        }
    }
}
