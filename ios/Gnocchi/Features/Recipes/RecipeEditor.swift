import ImageIO
import PhotosUI
import SwiftUI

struct RecipeEditor: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe?
    private let replacingFromImport: Bool
    private let applyDraft: ((RecipeDraft) -> Void)?
    @State private var initial: RecipeDraft
    @State private var draft: RecipeDraft
    @State private var newID = UUID().uuidString
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var uploadedURL: String?
    @State private var loadingPhoto = false
    @State private var saving = false
    @State private var confirmingDiscard = false
    @State private var error: String?

    init(recipe: Recipe? = nil, imported: RecipeDraft? = nil, folderID: String? = nil,
         applyDraft: ((RecipeDraft) -> Void)? = nil) {
        self.recipe = recipe
        self.applyDraft = applyDraft
        replacingFromImport = recipe != nil && imported != nil
        var value = RecipeDraft(recipe: recipe)
        if recipe == nil, folderID != RecipeFilters.unfiled { value.folderID = folderID }
        var edited = imported ?? value
        if recipe == nil, let folderID, folderID != RecipeFilters.unfiled { edited.folderID = folderID }
        _photoData = State(initialValue: edited.importedCover.flatMap { RecipePhoto.jpeg(from: $0, maxPixelSize: 2_000) })
        _initial = State(initialValue: applyDraft == nil ? value : edited)
        if applyDraft == nil { edited.importedCover = nil }
        _draft = State(initialValue: edited)
    }

    private var hasEdits: Bool { draft != initial || (applyDraft == nil && photoData != nil) }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Rezepttitel", text: $draft.title, prompt: Text("Rezepttitel").foregroundStyle(Theme.recipeSecondary))
                .font(Theme.display(32, relativeTo: .title))
            TextField("Untertitel", text: $draft.subtitle, prompt: Text("Untertitel").foregroundStyle(Theme.recipeSecondary))
                .font(.subheadline)
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(Theme.gutter)
        .frame(maxWidth: .infinity, minHeight: 182, alignment: .bottomLeading)
        .background {
            GeometryReader { proxy in
                heroArtwork
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                    }
            }
            .accessibilityHidden(true)
        }
        .clipShape(.rect(cornerRadius: Theme.radiusCard))
    }

    @ViewBuilder private var heroArtwork: some View {
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image).resizable()
        } else {
            let url = draft.imagePath.flatMap { URL(string: $0, relativeTo: Backend.site)?.absoluteURL }
            CatalogImage(url: url) { image in
                image.resizable()
            } placeholder: {
                LinearGradient(colors: [Theme.photoPlaceholder, RecipeDetailPhoto.neutralBackdrop],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    var body: some View {
        let photoActionTitle = photoData == nil && draft.imagePath == nil ? "Foto auswählen" : "Foto ändern"
        Form {
            hero
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if replacingFromImport, let recipe {
                Section {
                    Text("Beim Sichern werden die Rezeptangaben und Zutaten von „\(recipe.title)“ aktualisiert.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(photoActionTitle, systemImage: "photo")
                }
                if loadingPhoto { ProgressView("Foto wird geladen") }
                if photoData != nil || draft.imagePath != nil {
                    Button("Foto entfernen", role: .destructive) {
                        photo = nil
                        photoData = nil
                        uploadedURL = nil
                        draft.imagePath = nil
                        draft.importedCover = nil
                    }
                }
            }
            Section("Details") {
                TextField("Quelle", text: $draft.source)
                Picker("Ernährung", selection: $draft.diet) {
                    Text("Keine Angabe").tag(nil as String?)
                    Text("Vegetarisch").tag(Optional("vegetarisch"))
                    Text("Fisch").tag(Optional("fisch"))
                    Text("Fleisch").tag(Optional("fleisch"))
                }
            }
            Section("Zeit und Menge") {
                TextField("Zeit, z. B. ca. 30 Min.", text: $draft.timeText)
                LabeledContent("Minuten") {
                    TextField("Optional", text: $draft.timeMin)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Minuten")
                }
                LabeledContent("Portionen") {
                    TextField("Optional", text: $draft.servings)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Portionen")
                }
                TextField("Menge, z. B. 1 Blech", text: $draft.servingsText)
            }
            Section {
                ForEach($draft.ingredients) { $ingredient in
                    VStack(alignment: .leading) {
                        TextField("Zutat", text: $ingredient.name)
                        TextField("Menge, z. B. 250 g", text: $ingredient.amount).font(.subheadline)
                        TextField("Gruppe, z. B. Für die Sauce", text: $ingredient.group).font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { draft.ingredients.remove(atOffsets: $0) }
                .onMove { draft.ingredients.move(fromOffsets: $0, toOffset: $1) }
                Button("Zutat hinzufügen", systemImage: "plus") { draft.ingredients.append(.init()) }
            } header: {
                Text("Zutaten")
            }
            Section {
                TextField("Schritte", text: $draft.steps, axis: .vertical).lineLimit(3...12)
                TextField("Tipp", text: $draft.tip, axis: .vertical)
            } header: {
                Text("Zubereitung")
            } footer: {
                Text("Trenne die Schritte durch eine Leerzeile.")
                if !draft.missingPreparationIngredients.isEmpty {
                    Text("In den Schritten prüfen: \(draft.missingPreparationIngredients.joined(separator: ", "))")
                }
            }
            Section("Nährwerte pro Portion") {
                TextField("442 kcal | Fett 23,7 g | Eiweiß 42 g", text: $draft.nutritionText, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityLabel("Nährwerte pro Portion")
                if !draft.nutritionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Picker("Angabe", selection: $draft.nutritionEstimated) {
                        Text("Laut Rezept").tag(false)
                        Text("Geschätzt").tag(true)
                    }
                }
            }
            Section("Preis pro Portion") {
                TextField("Betrag in Euro", text: Binding(get: { draft.priceText }, set: {
                    draft.priceText = $0
                    draft.priceEstimated = false
                }))
                .keyboardType(.decimalPad)
                if !draft.priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   FoodMoney.cents(from: draft.priceText) == nil {
                    Text("Gib einen Eurobetrag mit bis zu zwei Nachkommastellen ein.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Sammlung") {
                Picker("Ordner", selection: $draft.folderID) {
                    Text("Kein Ordner").tag(nil as String?)
                    ForEach(store.folders) { Text($0.label).tag(Optional($0.id)) }
                }
                TextField("Tags mit Kommas trennen", text: $draft.tags)
                Picker("Kochbuch", selection: $draft.cookbookID) {
                    Text("Kein Kochbuch").tag(nil as String?)
                    ForEach(store.cookbooks) { Text($0.title).tag(Optional($0.id)) }
                    if let book = draft.importedBook, !store.cookbooks.contains(where: { $0.id == book.id }) {
                        Text("\(book.title) (neu)").tag(Optional(book.id))
                    }
                }
                if draft.cookbookID != nil {
                    TextField("Seite", text: $draft.cookbookPage).keyboardType(.numberPad)
                    Toggle("Verknüpfung bestätigt", isOn: $draft.bookConfirmed)
                }
            }
        }
        .disabled(saving)
        .navigationTitle(applyDraft != nil ? "Entwurf bearbeiten" : replacingFromImport ? "Rezept aktualisieren" :
                         recipe == nil ? "Neues Rezept" : "Rezept bearbeiten")
        .navigationBarBackButtonHidden(applyDraft != nil)
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", systemImage: "xmark") {
                    if hasEdits { confirmingDiscard = true } else { dismiss() }
                }
                .labelStyle(.iconOnly)
                .disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView().accessibilityLabel("Speichert …") }
                    else if applyDraft != nil { Text("Übernehmen") }
                    else { Label("Sichern", systemImage: "checkmark").labelStyle(.iconOnly) }
                }
                .disabled(!draft.valid || saving || loadingPhoto || !hasEdits)
            }
            ToolbarItem(placement: .bottomBar) {
                if draft.ingredients.count > 1 { EditButton() }
            }
        }
        .interactiveDismissDisabled(saving || hasEdits)
        .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Änderungen verwerfen", role: .destructive) { dismiss() }
            Button("Weiter bearbeiten", role: .cancel) {}
        }
        .alert("Rezept", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .task(id: photo) {
            guard let photo else { loadingPhoto = false; return }
            loadingPhoto = true
            do {
                guard let data = try await photo.loadTransferable(type: Data.self),
                      let jpeg = RecipePhoto.jpeg(from: data, maxPixelSize: 2_000) else { throw URLError(.cannotDecodeContentData) }
                guard !Task.isCancelled else { return }
                photoData = jpeg
                if applyDraft != nil { draft.importedCover = jpeg }
                uploadedURL = nil
            } catch {
                if !Task.isCancelled { self.error = "Das Foto konnte nicht geladen werden." }
            }
            if !Task.isCancelled { loadingPhoto = false }
        }
    }

    private func save() async {
        guard !saving, draft.valid else { return }
        if let applyDraft {
            applyDraft(draft)
            dismiss()
            return
        }
        saving = true
        defer { saving = false }
        do {
            if let photoData, !store.isDemo {
                if uploadedURL == nil { uploadedURL = try await store.uploadRecipePhoto(photoData) }
                draft.imagePath = uploadedURL
            }
            try await store.saveRecipe(id: recipe?.id ?? newID, expectedRevision: recipe?.updatedAt,
                                       draft: draft, replacingIngredients: recipe == nil || draft.ingredients != initial.ingredients)
            dismiss()
        } catch let failure as RecipeSaveFailure {
            error = failure.message
        } catch {
            self.error = "Das Rezept konnte nicht gesichert werden. Deine Eingaben sind noch da."
        }
    }

}

enum RecipePhoto {
    static func jpeg(from data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85)
    }
}
