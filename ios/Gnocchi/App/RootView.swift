import SwiftUI

/// Angemeldet: Startbildschirm. Sonst Anmelden.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
        case .signedOut:
            LoginView()
        case let .signedIn(email):
            HomePlaceholderView(email: email)
        }
    }
}

/// Platzhalter, bis Woche, Einkauf und Spielen nativ gebaut sind.
/// Zeigt, dass Anmeldung und Datenbank aus der App heraus funktionieren.
struct HomePlaceholderView: View {
    @Environment(SessionStore.self) private var session
    let email: String
    @State private var serverOffset: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Konto") {
                    LabeledContent("Angemeldet als", value: email)
                }
                Section("Verbindung") {
                    LabeledContent("Uhr zum Server", value: serverOffset ?? "…")
                }
                Section {
                    Button("Abmelden", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
            }
            .navigationTitle("Gnocchi")
            .task { serverOffset = await session.serverClockOffsetText() }
        }
    }
}
