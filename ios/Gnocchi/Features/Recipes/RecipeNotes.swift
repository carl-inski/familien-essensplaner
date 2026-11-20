import SwiftUI

struct RecipeNotes: View {
    @Environment(HouseholdStore.self) private var store
    let recipeID: String
    @State private var editor: EditorRoute?
    @State private var pendingDelete: RecipeNote?
    @State private var showingDelete = false
    @State private var deleting = false
    @State private var loadFailed = false
    @State private var deleteFailed = false

    private struct EditorRoute: Identifiable {
        let id = UUID()
        let note: RecipeNote?
    }

    var body: some View {
        RecipePanel("Notizen") {
            if let notes = store.recipeNotes[recipeID] {
                ForEach(notes) { note in
                    row(note)
                }
            } else if loadFailed {
                Button("Notizen erneut laden", systemImage: "arrow.clockwise") {
                    Task { await reload() }
                }
            } else if !store.isDemo {
                ProgressView().accessibilityLabel("Notizen werden geladen")
            }
            if let editor {
                RecipeNoteEditor(recipeID: recipeID, note: editor.note) { self.editor = nil }
                    .id(editor.id)
            } else {
                Button("Notiz hinzufügen", systemImage: "square.and.pencil") {
                    editor = EditorRoute(note: nil)
                }
            }
        }
        .task(id: recipeID) {
            await reload()
            if !Task.isCancelled { await store.watchRecipeNotes(for: recipeID) }
        }
        .confirmationDialog("Notiz löschen?", isPresented: $showingDelete, titleVisibility: .visible,
                            presenting: pendingDelete) { note in
            Button("Notiz löschen", role: .destructive) { Task { await remove(note) } }
        }
        .alert("Die Notiz konnte nicht gelöscht werden.", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ note: RecipeNote) -> some View {
        let author = store.members.first(where: { $0.id == note.member_id })?.name ?? "Ehemaliges Mitglied"
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack { attribution(author, note: note) }
                    VStack(alignment: .leading) { attribution(author, note: note) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(note.body).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if store.canEditNote(note) {
                Menu {
                    Button("Bearbeiten", systemImage: "pencil") { editor = EditorRoute(note: note) }
                    Button("Löschen", systemImage: "trash", role: .destructive) {
                        pendingDelete = note
                        showingDelete = true
                    }
                } label: {
                    Label("Aktionen für Notiz von \(author)", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(deleting)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func attribution(_ author: String, note: RecipeNote) -> some View {
        Text(author).font(.subheadline.weight(.semibold))
        if let createdAt = note.createdAt {
            Text(createdAt, format: .dateTime.day().month(.abbreviated).year())
        }
        if note.created_at != note.updated_at { Text("Bearbeitet") }
    }

    private func reload() async {
        do {
            try await store.loadRecipeNotes(for: recipeID)
            loadFailed = false
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    private func remove(_ note: RecipeNote) async {
        deleting = true
        defer { deleting = false }
        do { try await store.deleteRecipeNote(note, recipeID: recipeID) }
        catch { deleteFailed = true }
    }
}

private struct RecipeNoteEditor: View {
    @Environment(HouseholdStore.self) private var store
    @FocusState private var focused: Bool
    @State private var id = UUID().uuidString
    @State private var text: String
    @State private var saving = false
    @State private var saveError: String?
    let recipeID: String
    let note: RecipeNote?
    let close: () -> Void

    init(recipeID: String, note: RecipeNote?, close: @escaping () -> Void) {
        self.recipeID = recipeID
        self.note = note
        self.close = close
        _text = State(initialValue: note?.body ?? "")
    }

    private var length: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Zum Beispiel weniger Chili", text: $text, axis: .vertical)
                .lineLimit(2...8)
                .padding(12)
                .background(Theme.recipeHighlight, in: .rect(cornerRadius: 12))
                .focused($focused)
                .accessibilityLabel("Notiz")
                .disabled(saving)
            if length > 4000 { Text("Höchstens 4000 Zeichen").font(.footnote) }
            if let saveError { Text(saveError).font(.footnote) }
            HStack {
                Button("Abbrechen", action: close).disabled(saving)
                Spacer()
                Button("Sichern") { Task { await save() } }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(saving || !(1...4000).contains(length))
            }
        }
        .defaultFocus($focused, true)
    }

    private func save() async {
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            try await store.saveRecipeNote(id: id, recipeID: recipeID, body: text, editing: note)
            close()
        } catch {
            saveError = "Die Notiz konnte nicht gesichert werden. Versuch es erneut."
        }
    }
}
