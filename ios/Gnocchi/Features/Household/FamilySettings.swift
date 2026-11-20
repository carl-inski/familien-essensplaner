import GnocchiCore
import PhotosUI
import SwiftUI

struct StandardWeekView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let member: Member
    @State private var week: [String: [Meal: AttendanceStatus]]
    @State private var meal: Meal = .dinner
    @State private var saving = false
    @State private var failed = false
    private let weekdays = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    init(member: Member) {
        self.member = member
        _week = State(initialValue: member.defaultWeek)
    }

    var body: some View {
        Form {
            Picker("Mahlzeit", selection: $meal) {
                ForEach(Meal.planned, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Section {
                ForEach(Array(zip(StandardWeek.days, weekdays)), id: \.0) { key, label in
                    Toggle(label, isOn: Binding(
                        get: { week[key]?[meal] != .away },
                        set: { week = StandardWeek.updating(week, day: key, meal: meal, present: $0) }
                    ))
                }
            } header: {
                Text("Isst normalerweise mit")
            } footer: {
                Text("Einträge für einzelne Mahlzeiten im Wochenplan haben Vorrang.")
            }
        }
        .navigationTitle(member.name)
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(saving) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    Task {
                        saving = true
                        defer { saving = false }
                        do {
                            try await store.saveStandardWeek(week, memberID: member.id)
                            dismiss()
                        } catch { failed = true }
                    }
                }
                .disabled(saving || week == member.defaultWeek)
            }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving || week != member.defaultWeek)
        .alert("Standardwoche konnte nicht gespeichert werden.", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }
}

struct MemberForm: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let member: Member?
    @State private var id: String
    @State private var name: String
    @State private var email: String
    @State private var admin: Bool
    @State private var password = ""
    @State private var saved = false
    @State private var saving = false
    @State private var error: String?

    init(member: Member?) {
        self.member = member
        _id = State(initialValue: member?.id ?? UUID().uuidString)
        _name = State(initialValue: member?.name ?? "")
        _email = State(initialValue: member?.email ?? "")
        _admin = State(initialValue: member?.isAdmin ?? false)
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var body: some View {
        Form {
            if let member, !store.isDemo {
                MemberPhotoSection(memberID: member.id)
            }
            Section("Mitglied") {
                TextField("Name", text: $name).textContentType(.name)
                TextField("E-Mail (optional)", text: $email)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Admin", isOn: $admin).disabled(id == store.household?.memberID)
            }
            if !store.isDemo {
                Section {
                    SecureField("Passwort (optional)", text: $password).textContentType(.newPassword)
                } header: {
                    Text("Familienverwalteter Login")
                } footer: {
                    Text("Mit E-Mail und mindestens 8 Zeichen. Ein selbst registriertes Konto verwaltet sein Passwort selbst.")
                }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(member == nil ? "Neues Mitglied" : "Mitglied bearbeiten")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { Task { await save() } }
                    .disabled(cleanName.isEmpty || cleanName.count > 40 || saving ||
                              (!password.isEmpty && (password.count < 8 || cleanEmail.isEmpty)))
            }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await store.saveMember(id: id, existing: saved || member != nil, name: cleanName, email: cleanEmail, admin: admin)
            saved = true
            if !password.isEmpty { try await store.setMemberPassword(password, memberID: id) }
            dismiss()
        } catch let failure as HouseholdEditError {
            error = failure.errorDescription
        } catch {
            self.error = "Das Mitglied konnte nicht gespeichert werden."
        }
    }
}

struct MemberPhotoSection: View {
    @Environment(HouseholdStore.self) private var store
    let memberID: String
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        let avatar = store.members.first { $0.id == memberID }?.avatarURL
        Section("Profilbild") {
            HStack(spacing: 14) {
                AsyncImage(url: avatar.flatMap { URL(string: $0) }) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(.secondary) }
                }
                .frame(width: 48, height: 48).clipShape(Circle()).accessibilityHidden(true)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Foto auswählen", systemImage: "photo")
                }.buttonStyle(.borderless)
                if busy { ProgressView().accessibilityLabel("Profilbild wird gespeichert") }
            }
            if avatar != nil {
                Button("Profilbild entfernen", role: .destructive) { Task { await save(nil) } }
            }
        }
        .disabled(busy)
        .onChange(of: photo) {
            guard let photo, !busy else { return }
            Task {
                busy = true
                defer { busy = false; self.photo = nil }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self),
                          let resized = RecipePhoto.jpeg(from: data, maxPixelSize: 640) else {
                        throw HouseholdEditError.unavailable
                    }
                    try await store.saveMemberPhoto(resized, memberID: memberID)
                } catch { failed = true }
            }
        }
        .alert("Das Profilbild konnte nicht geändert werden.", isPresented: $failed) { Button("OK", role: .cancel) {} }
    }

    private func save(_ data: Data?) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await store.saveMemberPhoto(data, memberID: memberID) }
        catch { failed = true }
    }
}

struct RenameFamilyForm: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        Form { TextField("Name der Familie", text: $name) }
            .navigationTitle("Familienname")
            .gnScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            saving = true
                            defer { saving = false }
                            do {
                                try await store.renameFamily(name.trimmingCharacters(in: .whitespacesAndNewlines))
                                dismiss()
                            } catch { failed = true }
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60)
                }
            }
            .interactiveDismissDisabled(saving)
            .alert("Der Familienname konnte nicht gespeichert werden.", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
    }
}

struct PasswordForm: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var saving = false
    @State private var failed = false
    var recovery = false

    var body: some View {
        Form {
            Section {
                SecureField("Neues Passwort", text: $password).textContentType(.newPassword)
                SecureField("Passwort wiederholen", text: $confirmation).textContentType(.newPassword)
            } footer: {
                Text(confirmation.isEmpty || password == confirmation ? "Mindestens 8 Zeichen." : "Die Passwörter stimmen noch nicht überein.")
            }
        }
        .navigationTitle("Passwort ändern")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        if recovery { Task { await session.signOut() } }
                        else { dismiss() }
                    }
                    .disabled(saving)
                }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    Task {
                        saving = true
                        defer { saving = false }
                        do {
                            try await session.changePassword(password)
                            dismiss()
                        } catch { failed = true }
                    }
                }
                .disabled(saving || password.count < 8 || password != confirmation)
            }
        }
        .interactiveDismissDisabled(saving)
        .alert("Das Passwort konnte nicht geändert werden.", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }
}
