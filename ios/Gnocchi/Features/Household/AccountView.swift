import GnocchiCore
import SwiftUI

/// Einstellungen: eine kurze Hauptseite, alles Weitere eine Ebene tiefer.
struct AccountView: View {
    @Environment(NavigationChrome.self) private var chrome
    @Environment(SessionStore.self) private var session
    @Environment(HouseholdStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    let email: String
    @State private var sheet: AccountSheet?
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleteFailed: String?
    @State private var collectionExport: RecipeMarkdownDocument?
    @State private var collectionExportFailed = false

    private var me: Member? { store.members.first { $0.id == store.household?.memberID } }

    var body: some View {
        @Bindable var preferences = preferences
        List {
            if let family = store.household {
                Section {
                    NavigationLink {
                        InviteView(family: family)
                    } label: {
                        InviteBanner(family: family.name, people: store.members.count)
                    }
                    .listRowBackground(Theme.ink)
                    .foregroundStyle(Theme.onInk)
                }
                Section("Familie") {
                    NavigationLink {
                        MembersView()
                    } label: {
                        SettingsRow("Mitglieder", symbol: "person.2.fill", color: Theme.accent,
                                    value: String(store.members.count))
                    }
                    NavigationLink {
                        StandardWeekList()
                    } label: {
                        SettingsRow("Standardwoche", symbol: "calendar", color: Theme.accent)
                    }
                    NavigationLink {
                        FamiliesView()
                    } label: {
                        SettingsRow("Familie wechseln", symbol: "arrow.left.arrow.right", color: Theme.accent,
                                    value: store.memberships.count > 1 ? family.name : nil)
                    }
                }
                Section("Küche") {
                    NavigationLink {
                        WeeklyBudgetSettings(family: family)
                    } label: {
                        SettingsRow("Wochenbudget", symbol: "eurosign.circle", color: Theme.accent)
                    }
                    Button {
                        collectionExport = RecipeMarkdownDocument(recipes: store.recipes, books: store.cookbooks)
                    } label: {
                        SettingsRow("Rezepte als Markdown exportieren", symbol: "square.and.arrow.down", color: Theme.accent)
                    }
                    .disabled(store.recipes.isEmpty)
                    NavigationLink {
                        IngredientEmojiCatalogView()
                    } label: {
                        SettingsRow("Zutaten-Emojis", symbol: "books.vertical", color: Theme.accent)
                    }
                    NavigationLink {
                        MissingIngredientEmojisView()
                    } label: {
                        SettingsRow("Fehlende Zutaten-Emojis", symbol: "face.smiling", color: Theme.accent)
                    }
                    NavigationLink {
                        AssistantSettingsView()
                    } label: {
                        SettingsRow("KI und Nutzung", symbol: "sparkles", color: Theme.accent)
                    }
                }
            } else if !store.memberships.isEmpty {
                Section("Familie") {
                    NavigationLink {
                        FamiliesView()
                    } label: {
                        SettingsRow("Familie auswählen", symbol: "person.2.fill", color: Theme.accent)
                    }
                }
            } else if store.loaded {
                ContentUnavailableView("Noch keine Familie", systemImage: "person.2")
                    .listRowBackground(Color.clear)
                if !store.isDemo {
                    Section {
                        Button { sheet = .create } label: {
                            SettingsRow("Familie anlegen", symbol: "person.2.badge.plus", color: Theme.accent)
                        }
                        Button { sheet = .join } label: {
                            SettingsRow("Mit Einladungscode beitreten", symbol: "key.fill", color: Theme.accent)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } else {
                Button("Erneut laden") { Task { await store.load() } }
            }
            Section {
                let hapticsSwitch = Toggle(isOn: $preferences.hapticsEnabled) {
                    SettingsRow("Haptisches Feedback", symbol: "hand.tap.fill", color: Theme.accent)
                }
                Button {
                    preferences.hapticsEnabled.toggle()
                } label: {
                    hapticsSwitch
                        .allowsHitTesting(false)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityRepresentation { hapticsSwitch }
            } header: {
                Text("App")
            }
            Section("Konto") {
                if !store.isDemo, let memberID = store.household?.memberID {
                    NavigationLink {
                        List { MemberPhotoSection(memberID: memberID) }
                            .navigationTitle("Profilbild")
                            .navigationBarTitleDisplayMode(.inline)
                            .gnScreen()
                    } label: {
                        SettingsRow("Profilbild", symbol: "person.crop.circle.fill", color: Theme.accent)
                    }
                }
                if !store.isDemo {
                    Button { sheet = .password } label: {
                        SettingsRow("Passwort ändern", symbol: "key.fill", color: Theme.inkSecondary)
                    }
                    .foregroundStyle(.primary)
                    Button { confirmSignOut = true } label: {
                        SettingsRow("Abmelden", symbol: "rectangle.portrait.and.arrow.right", color: .red)
                    }
                    .foregroundStyle(.primary)
                    Button { confirmDelete = true } label: {
                        SettingsRow("Konto löschen", symbol: "trash.fill", color: .red)
                    }
                    .foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let me { Text(me.name).font(.subheadline.weight(.medium)) }
                    Text(email).font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Angemeldet als \(me?.name ?? email), \(email)")
            }
        }
        .navigationTitle("Einstellungen")
        .toolbar(.hidden, for: .tabBar)
        .onAppear { chrome.hideActions() }
        .gnScreen()
        .refreshable {
            await store.load()
            await store.loadCookingHistory()
        }
        .fileExporter(isPresented: Binding(get: { collectionExport != nil },
                                           set: { if !$0 { collectionExport = nil } }),
                      document: collectionExport, contentType: RecipeMarkdownDocument.markdown,
                      defaultFilename: "rezeptsammlung.md") { result in
            if case .failure = result { collectionExportFailed = true }
        }
        .alert("Die Sammlung konnte nicht exportiert werden.", isPresented: $collectionExportFailed) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $sheet) { $0.content }
        .confirmationDialog("Abmelden?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await session.signOut() } }
        }
        .confirmationDialog("Konto endgültig löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) {
                Task {
                    do { try await session.deleteAccount() } catch {
                        deleteFailed = "Das Konto konnte nicht gelöscht werden. Bitte versuch es noch einmal."
                    }
                }
            }
        } message: {
            Text("Login und E-Mail-Adresse werden entfernt. Familien, in denen sonst niemand ein Konto hat, werden mit allen Rezepten und Plänen gelöscht. Das lässt sich nicht rückgängig machen.")
        }
        .alert(deleteFailed ?? "", isPresented: Binding(get: { deleteFailed != nil }, set: { if !$0 { deleteFailed = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

/// Formulare, die von mehreren Einstellungsseiten aus geöffnet werden.
private enum AccountSheet: String, Identifiable {
    case create, join, rename, password, member
    var id: Self { self }

    @MainActor @ViewBuilder var content: some View {
        NavigationStack {
            switch self {
            case .create, .join: FamilyForm(creating: self == .create)
            case .rename: RenameFamilyFormHost()
            case .password: PasswordForm()
            case .member: MemberForm(member: nil)
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct RenameFamilyFormHost: View {
    @Environment(HouseholdStore.self) private var store
    var body: some View { RenameFamilyForm(name: store.household?.name ?? "") }
}

/// Eine Zeile mit farbigem Symbol, Titel und optionalem Wert rechts.
struct SettingsRow: View {
    let title: String
    let symbol: String
    let color: Color
    var value: String?

    init(_ title: String, symbol: String, color: Color, value: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.value = value
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: .rect(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            if let value {
                Text(value).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// Dunkle Karte ganz oben: lädt dazu ein, die Familie zu vervollständigen.
private struct InviteBanner: View {
    let family: String
    let people: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.badge.plus")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Theme.onInk.opacity(0.14), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(family).font(.headline)
                Text(people == 1 ? "Noch allein am Tisch. Lade jemanden ein." : "\(people) am Tisch · Einladen und Code")
                    .font(.subheadline)
                    .foregroundStyle(Theme.onInk.opacity(0.65))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet Einladungscode und Familienname.")
    }
}

/// Einladungscode, Links zum Teilen, Familienname.
private struct InviteView: View {
    @Environment(HouseholdStore.self) private var store
    let family: Membership
    @State private var renewCode = false
    @State private var changingCode = false
    @State private var sheet: AccountSheet?

    var body: some View {
        let name = store.household?.name ?? family.name
        List {
            if let code = store.inviteCode {
                let pretty = code.prefix(4) + "-" + code.dropFirst(4)
                Section {
                    VStack(spacing: 10) {
                        Text(pretty)
                            .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                            .textSelection(.enabled)
                            .accessibilityLabel("Einladungscode \(code.map(String.init).joined(separator: " "))")
                        Text("Mit diesem Code kommt jemand zu „\(name)“.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                if !store.isDemo {
                    Section {
                        let url = Backend.site.appending(path: "beitreten").appending(queryItems: [
                            URLQueryItem(name: "code", value: code)
                        ])
                        ShareLink(item: AppShareText.withFooter("Komm zu „\(name)“ in Gnocchi. Code: \(pretty)\n\(url.absoluteString)")) {
                            SettingsRow("Einladung teilen", symbol: "square.and.arrow.up", color: Theme.accent)
                        }
                        if let appURL = URL(string: "gnocchi://beitreten")?.appending(queryItems: [
                            URLQueryItem(name: "code", value: code)
                        ]) {
                            ShareLink(item: AppShareText.withFooter("Komm zu „\(name)“ in Gnocchi. Code: \(pretty)\n\(appURL.absoluteString)")) {
                                SettingsRow("Link für die iPhone-App teilen", symbol: "iphone", color: Theme.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            if store.isAdmin {
                Section {
                    Button { sheet = .rename } label: {
                        SettingsRow("Familie umbenennen", symbol: "pencil", color: Theme.inkSecondary)
                    }
                    if store.inviteCode != nil {
                        Button { renewCode = true } label: {
                            SettingsRow("Neuen Code erzeugen", symbol: "arrow.clockwise", color: Theme.accent)
                        }
                        .disabled(changingCode)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Einladen")
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .sheet(item: $sheet) { $0.content }
        .confirmationDialog("Neuen Einladungscode erzeugen?", isPresented: $renewCode, titleVisibility: .visible) {
            Button("Neuen Code erzeugen", role: .destructive) {
                Task {
                    changingCode = true
                    defer { changingCode = false }
                    do { try await store.regenerateInvite() }
                    catch { store.error = "Ein neuer Code konnte nicht erzeugt werden." }
                }
            }
        } message: {
            Text("Der bisherige Code und die bisherigen Einladungslinks werden ungültig.")
        }
    }
}

/// Wer zur Familie gehört und wie oft jede Person zuletzt gekocht hat.
private struct MembersView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var sheet: AccountSheet?

    var body: some View {
        List {
            Section {
                ForEach(store.members) { member in
                    if store.isAdmin {
                        NavigationLink {
                            MemberForm(member: member)
                        } label: { memberLabel(member) }
                    } else {
                        memberLabel(member)
                    }
                }
            } footer: {
                Text("Die Zahl rechts zeigt den Kochdienst der letzten 4 Wochen.")
            }
            if store.isAdmin {
                Section {
                    Button { sheet = .member } label: {
                        SettingsRow("Mitglied hinzufügen", symbol: "person.badge.plus", color: Theme.accent)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Mitglieder")
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .sheet(item: $sheet) { $0.content }
    }

    private func memberLabel(_ member: Member) -> some View {
        let cooked = store.cookCounts[member.id, default: 0]
        return HStack(spacing: 12) {
            MealMemberAvatar(member: member, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.id == store.household?.memberID ? "\(member.name) (du)" : member.name)
                Text(member.isAdmin ? "Admin" : member.hasLogin ? "Mit Login" : "Ohne Login")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Label("\(cooked)", systemImage: "frying.pan")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(cooked) Mal gekocht in den letzten 4 Wochen")
        }
        .accessibilityElement(children: .combine)
    }
}

/// Standardwoche je Person.
private struct StandardWeekList: View {
    @Environment(HouseholdStore.self) private var store
    @State private var editing: Member?

    var body: some View {
        List {
            Section {
                ForEach(store.members) { member in
                    Button {
                        editing = member
                    } label: {
                        HStack(spacing: 12) {
                            MealMemberAvatar(member: member, size: 34)
                            Text(member.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("Leg fest, wer mittags und abends normalerweise mitisst.")
            }
        }
        .navigationTitle("Standardwoche")
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .sheet(item: $editing) { member in
            NavigationStack { StandardWeekView(member: member) }
                .presentationDragIndicator(.visible)
        }
    }
}

/// Zwischen Familien wechseln, eine anlegen, einer beitreten oder die aktive verlassen.
private struct FamiliesView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var sheet: AccountSheet?
    @State private var confirmLeave = false

    var body: some View {
        List {
            if !store.memberships.isEmpty {
                Section {
                    ForEach(store.memberships) { family in
                        Button {
                            Task { await store.switchHousehold(to: family.id) }
                        } label: {
                            HStack {
                                Text(family.name)
                                Spacer()
                                if store.household?.id == family.id {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.accent)
                                        .accessibilityLabel("Aktive Familie")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                        .disabled(store.saving || store.household?.id == family.id)
                    }
                }
            }
            if store.loaded && !store.isDemo {
                Section {
                    Button { sheet = .create } label: {
                        SettingsRow("Familie anlegen", symbol: "person.2.badge.plus", color: Theme.accent)
                    }
                    Button { sheet = .join } label: {
                        SettingsRow("Mit Einladungscode beitreten", symbol: "key.fill", color: Theme.accent)
                    }
                }
                .foregroundStyle(.primary)
            }
            if store.household != nil && !store.isDemo {
                Section {
                    Button("Familie verlassen", role: .destructive) { confirmLeave = true }
                        .disabled(store.saving)
                }
            }
        }
        .navigationTitle("Familien")
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .sheet(item: $sheet) { $0.content }
        .confirmationDialog("Familie verlassen?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Familie verlassen", role: .destructive) {
                Task { await store.leaveFamily() }
            }
        } message: {
            Text("Rezepte und Plan bleiben in der Familie. Zum Wiedereintritt brauchst du einen Einladungscode.")
        }
    }
}

struct FamilyForm: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let creating: Bool
    @State private var name = ""
    @State private var family = ""
    @State private var code: String
    @State private var invite: InvitePreview?
    @State private var checkedCode: String?

    init(creating: Bool, initialCode: String = "") {
        self.creating = creating
        _code = State(initialValue: initialCode)
    }

    private var normalizedCode: String {
        String(code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    var body: some View {
        Form {
            if creating {
                TextField("Name der Familie", text: $family)
            } else {
                TextField("Einladungscode", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if let invite, checkedCode == normalizedCode {
                    LabeledContent(invite.household_name, value: "\(invite.member_count) Personen")
                } else if normalizedCode.count == 8, checkedCode == normalizedCode {
                    Text("Diese Einladung wurde nicht gefunden.").foregroundStyle(.secondary)
                }
            }
            TextField("Dein Name", text: $name)
                .textContentType(.givenName)
        }
        .navigationTitle(creating ? "Familie anlegen" : "Familie beitreten")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(creating ? "Anlegen" : "Beitreten") {
                    Task {
                        if creating {
                            await store.createHousehold(name: family, memberName: name)
                        } else {
                            await store.joinHousehold(code: normalizedCode, memberName: name)
                        }
                        if store.error == nil { dismiss() }
                    }
                }
                .disabled(store.saving || (store.isDemo && !creating) || name.count > 40 || (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && invite?.already_member != true)
                    || (creating ? family.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || family.count > 60
                                 : normalizedCode.count != 8))
            }
        }
        .interactiveDismissDisabled(store.saving)
        .onAppear {
            if name.isEmpty { name = session.displayName }
        }
        .task(id: normalizedCode) {
            let candidate = normalizedCode
            invite = nil
            checkedCode = nil
            guard !creating, !store.isDemo, candidate.count == 8 else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                let result = try await store.lookupInvite(candidate)
                guard !Task.isCancelled else { return }
                invite = result
                checkedCode = candidate
            } catch {
                // Joining still reports server errors when the preview is unavailable.
            }
        }
    }
}


private struct MissingIngredientEmojisView: View {
    @Environment(HouseholdStore.self) private var store

    private struct Entry: Identifiable {
        let name: String
        var recipes: [Recipe]
        var id: String { IngredientEmojiCatalog.key(name) }
    }

    private var entries: [Entry] {
        var missing: [String: Entry] = [:]
        for recipe in store.recipes {
            let names = IngredientEmojiCatalog.missingNames(in: recipe.ingredients.map(\.name))
            var seen: Set<String> = []
            for name in names {
                let key = IngredientEmojiCatalog.key(name)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                if missing[key] == nil { missing[key] = Entry(name: name, recipes: []) }
                missing[key]?.recipes.append(recipe)
            }
        }
        return missing.values.sorted {
            if $0.recipes.count == $1.recipes.count {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.recipes.count > $1.recipes.count
        }
    }

    var body: some View {
        let entries = entries
        List {
            if entries.isEmpty {
                ContentUnavailableView("Alle Zutaten haben ein Motiv", systemImage: "checkmark.circle",
                                       description: Text("Geprüft wurden die Zutaten deiner gespeicherten Rezepte."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(entries) { entry in
                        DisclosureGroup {
                            ForEach(entry.recipes) { recipe in
                                NavigationLink(recipe.title) { RecipeDetailView(recipe: recipe) }
                            }
                        } label: {
                            HStack {
                                Text(entry.name)
                                Spacer()
                                Text(entry.recipes.count, format: .number)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.inkSecondary)
                                    .accessibilityLabel(entry.recipes.count == 1 ? "1 Rezept" : "\(entry.recipes.count) Rezepte")
                            }
                        }
                    }
                } footer: {
                    Text("Zutaten aus deiner Rezeptsammlung ohne Motiv im Katalog. Häufig verwendete Zutaten stehen oben.")
                }
            }
        }
        .gnScreen()
        .navigationTitle("Fehlende Zutaten-Emojis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: entries.map { "\($0.name) · \($0.recipes.count)" }.joined(separator: "\n")) {
                        Label("Liste teilen", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
