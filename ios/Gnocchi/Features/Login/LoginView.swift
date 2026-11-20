import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @FocusState private var focus: Field?
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var accountAction: AccountAccessMode?

    private enum Field { case email, password }

    /// Öffnet direkt „Konto erstellen“, wenn das Onboarding dorthin führt.
    init(startRegistering: Bool = false) {
        _accountAction = State(initialValue: startRegistering ? .register : nil)
    }

    private var canSignIn: Bool {
        !busy && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Schön, dich zu sehen.")
                        .font(Theme.display(34))
                        .tracking(-0.6)
                        .accessibilityAddTraits(.isHeader)
                    Text("Melde dich an, dann geht es zurück an den Tisch.")
                        .font(.body)
                        .foregroundStyle(Theme.inkSecondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("E-Mail").font(.subheadline.weight(.medium)).accessibilityHidden(true)
                        TextField("E-Mail", text: $email, prompt: Text("name@beispiel.de"))
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .email)
                            .onSubmit { focus = .password }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Passwort").font(.subheadline.weight(.medium)).accessibilityHidden(true)
                        SecureField("Passwort", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focus, equals: .password)
                            .onSubmit(submit)
                    }
                }
                .gnCard(padding: 20)

                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }

                signInButton
                if session.inviteCode != nil {
                    Label("Melde dich an oder erstelle ein Konto, um die Einladung anzunehmen.", systemImage: "person.2")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button("Konto erstellen") { accountAction = .register }
                    Button("Passwort vergessen?") { accountAction = .reset }
                }
                .font(.subheadline)
                .disabled(busy)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 44)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { PaperBackground() }
        .sheet(item: $accountAction) { mode in
            NavigationStack { AccountAccessForm(mode: mode, initialEmail: email) }
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var signInButton: some View {
        button.buttonStyle(.ink)
    }

    private var button: some View {
        Button(action: submit) {
            Group {
                if busy {
                    ProgressView().accessibilityLabel("Wird angemeldet")
                } else {
                    Text("Anmelden")
                }
            }
        }
        .disabled(!canSignIn)
    }

    private func submit() {
        guard canSignIn else { return }
        focus = nil
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await session.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            } catch is URLError {
                self.error = "Die Verbindung ist gerade unterbrochen."
            } catch {
                self.error = "Die Anmeldung ist fehlgeschlagen. Prüfe deine Angaben."
            }
        }
    }
}

private enum AccountAccessMode: String, Identifiable {
    case register, reset
    var id: Self { self }
    var title: String { self == .register ? "Konto erstellen" : "Passwort zurücksetzen" }
}

private struct AccountAccessForm: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let mode: AccountAccessMode
    @State private var email: String
    @State private var name = ""
    @State private var password = ""
    @State private var busy = false
    @State private var status: String?
    @State private var error: String?

    init(mode: AccountAccessMode, initialEmail: String) {
        self.mode = mode
        _email = State(initialValue: initialEmail)
    }

    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            if let status {
                Section { Label(status, systemImage: "envelope") }
            } else {
                Section {
                    if mode == .register {
                        TextField("Dein Name", text: $name).textContentType(.givenName)
                    }
                    TextField("E-Mail", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    if mode == .register {
                        SecureField("Passwort", text: $password).textContentType(.newPassword)
                    }
                } footer: {
                    if mode == .register { Text("Das Passwort braucht mindestens 8 Zeichen.") }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
        }
        .navigationTitle(mode.title)
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(status == nil ? "Abbrechen" : "Fertig") { dismiss() }.disabled(busy)
            }
            if status == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .register ? "Erstellen" : "Link senden") { Task { await submit() } }
                        .disabled(busy || !cleanEmail.contains("@") ||
                                  (mode == .register && (cleanName.isEmpty || password.count < 8)))
                }
            }
        }
        .disabled(busy)
        .interactiveDismissDisabled(busy)
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if mode == .register {
                if try await session.register(email: cleanEmail, password: password, name: cleanName) {
                    dismiss()
                } else {
                    status = "Öffne den Bestätigungslink in deiner E-Mail auf diesem iPhone."
                }
            } else {
                try await session.requestPasswordReset(email: cleanEmail)
                status = "Falls es zu dieser Adresse ein Konto gibt, kommt eine E-Mail mit dem Link zum Zurücksetzen."
            }
        } catch {
            self.error = "Die Anfrage konnte nicht abgeschlossen werden. Prüfe die Angaben und versuche es erneut."
        }
    }
}
