import Foundation
import Observation
import Supabase

/// Anmeldestatus der App. Die Sitzung speichert supabase-swift im Schlüsselbund.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(email: String)
    }

    private(set) var state: State = .loading
    private let client = Backend.client

    func start() async {
        for await (_, session) in client.auth.authStateChanges {
            if let user = session?.user {
                state = .signedIn(email: user.email ?? "")
            } else {
                state = .signedOut
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    /// Abstand der Geräteuhr zur Serveruhr (ms), wie useServerOffset in der Web-App
    func serverClockOffsetText() async -> String {
        let t0 = Date().timeIntervalSince1970 * 1000
        do {
            let server: Double = try await client.rpc("ep_server_now").execute().value
            let t1 = Date().timeIntervalSince1970 * 1000
            let offset = server - (t0 + t1) / 2
            return "\(Int(offset.rounded())) ms (Laufzeit \(Int(t1 - t0)) ms)"
        } catch {
            return "nicht erreichbar"
        }
    }
}
