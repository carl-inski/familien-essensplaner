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
        case signedIn(id: UUID, email: String)
    }

    private(set) var state: State = .loading
    var recovering = false
    var linkError: String?
    var inviteCode: String?
    private(set) var displayName = ""
    private let client = Backend.client

    func start() async {
        for await (event, session) in client.auth.authStateChanges {
            if let user = session?.user {
                displayName = user.userMetadata["name"]?.stringValue ?? ""
                if event == .passwordRecovery { recovering = true }
                state = .signedIn(id: user.id, email: user.email ?? "")
            } else {
                displayName = ""
                recovering = false
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

    /// Löscht das Konto (RPC ep_delete_my_account, App-Store-Regel 5.1.1) und meldet ab.
    func deleteAccount() async throws {
        try await client.rpc("ep_delete_my_account").execute()
        try? await client.auth.signOut(scope: .local)
    }

    func changePassword(_ password: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password))
        recovering = false
    }

    func register(email: String, password: String, name: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password, data: ["name": .string(name)],
                                                   redirectTo: URL(string: "gnocchi://auth/confirm"))
        return response.session != nil
    }

    func requestPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: URL(string: "gnocchi://auth/recovery"))
    }

    func open(_ url: URL) async {
        guard url.scheme == "gnocchi", let host = url.host else { return }
        if host == "beitreten" {
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value ?? ""
            let normalized = code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            if normalized.count == 8 { inviteCode = normalized }
            return
        }
        guard host == "auth", ["/confirm", "/recovery"].contains(url.path) else { return }
        do {
            let session = try await client.auth.session(from: url)
            displayName = session.user.userMetadata["name"]?.stringValue ?? ""
            recovering = url.path == "/recovery"
            state = .signedIn(id: session.user.id, email: session.user.email ?? "")
        } catch {
            linkError = "Der Anmeldelink ist abgelaufen oder ungültig."
        }
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
