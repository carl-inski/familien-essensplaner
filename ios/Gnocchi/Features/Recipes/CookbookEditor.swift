import PhotosUI
import Supabase
import SwiftUI

struct CookbookEditor: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let book: Cookbook?
    @State private var id = UUID().uuidString
    @State private var title: String
    @State private var authors: String
    @State private var publisher: String
    @State private var year: String
    @State private var isbn: String
    @State private var coverPath: String?
    @State private var photo: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var uploadedCoverPath: String?
    @State private var loadingPhoto = false
    @State private var notes: String
    @State private var busy = false
    @State private var error: String?
    @State private var lookupSource: String?

    init(book: Cookbook? = nil) {
        self.book = book
        let displayed = book?.presented
        _title = State(initialValue: displayed?.title ?? "")
        _authors = State(initialValue: displayed?.authors.joined(separator: ", ") ?? "")
        _publisher = State(initialValue: displayed?.publisher ?? "")
        _year = State(initialValue: displayed?.year.map(String.init) ?? "")
        _isbn = State(initialValue: displayed?.isbn ?? "")
        _coverPath = State(initialValue: book?.coverPath)
        _notes = State(initialValue: displayed?.notes ?? "")
    }

    private var normalizedISBN: String {
        isbn.uppercased().filter { "0123456789X".contains($0) }
    }

    var body: some View {
        Form {
            coverPicker
            Section("Angaben") {
                TextField("Titel", text: $title)
                TextField("Autorinnen und Autoren", text: $authors)
                TextField("Verlag", text: $publisher)
                TextField("Erscheinungsjahr", text: $year).keyboardType(.numberPad)
            }
            Section {
                TextField("ISBN", text: $isbn).keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                if !store.isDemo {
                    Button("Buchdaten abrufen", systemImage: "magnifyingglass") { Task { await lookup() } }
                        .disabled(normalizedISBN.range(of: #"^(\d{9}[\dX]|\d{13})$"#, options: .regularExpression) == nil)
                }
            } header: {
                Text("ISBN")
            } footer: {
                if let lookupSource { Text("Angaben von \(lookupSource). Bitte prüfe sie vor dem Sichern.") }
            }
            Section("Notizen") {
                TextField("Notizen", text: $notes, axis: .vertical).lineLimit(2...6)
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .disabled(busy)
        .navigationTitle(book == nil ? "Buch hinzufügen" : "Buch bearbeiten")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }.disabled(busy)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { Task { await save() } }
                    .disabled(busy || loadingPhoto || cookbookField(title) == nil)
            }
        }
        .interactiveDismissDisabled(busy)
        .task(id: photo) { await loadSelectedPhoto() }
    }

    private var coverPicker: some View {
        let photoLabel = photoData == nil && coverPath == nil ? "Cover-Foto auswählen" : "Cover-Foto ändern"
        return Section("Cover") {
            if let photoData, let image = UIImage(data: photoData) {
                coverPreview(Image(uiImage: image))
            } else if let coverPath, let url = URL(string: coverPath, relativeTo: Backend.site)?.absoluteURL {
                CatalogImage(url: url, content: coverPreview) {
                    Image(systemName: "book.closed").foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 88)
                }
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label(photoLabel, systemImage: "photo")
            }
            if loadingPhoto { ProgressView("Foto wird geladen") }
            if photoData != nil || coverPath != nil {
                Button("Cover entfernen", role: .destructive) {
                    photo = nil
                    photoData = nil
                    uploadedCoverPath = nil
                    coverPath = nil
                }
            }
        }
    }

    private func coverPreview(_ image: Image) -> some View {
        image.resizable().scaledToFit().frame(height: 126)
            .clipShape(.rect(cornerRadius: 8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }

    private func loadSelectedPhoto() async {
        guard let photo else { loadingPhoto = false; return }
        loadingPhoto = true
        error = nil
        defer { if !Task.isCancelled { loadingPhoto = false } }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self),
                  let jpeg = RecipePhoto.jpeg(from: data, maxPixelSize: 1_600) else {
                throw URLError(.cannotDecodeContentData)
            }
            guard !Task.isCancelled else { return }
            photoData = jpeg
            uploadedCoverPath = nil
        } catch {
            if !Task.isCancelled { self.error = "Das Cover-Foto konnte nicht geladen werden." }
        }
    }

    private func save() async {
        guard !busy, !loadingPhoto, let title = cookbookField(title) else { return }
        let publicationYear = cookbookField(year)
        let number = publicationYear.flatMap(Int.init)
        guard publicationYear == nil || number.map({ (1...9999).contains($0) }) == true else {
            error = "Gib ein Erscheinungsjahr zwischen 1 und 9999 ein."
            return
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            if let photoData, uploadedCoverPath == nil {
                if store.isDemo {
                    let file = FileManager.default.temporaryDirectory.appending(path: "demo-cover-\(UUID().uuidString).jpg")
                    try photoData.write(to: file, options: .atomic)
                    uploadedCoverPath = file.absoluteString
                } else {
                    uploadedCoverPath = try await store.uploadRecipePhoto(photoData)
                }
            }
            let value = Cookbook(id: book?.id ?? id, title: title,
                                 authors: authors.split(separator: ",").compactMap { cookbookField(String($0)) },
                                 publisher: cookbookField(publisher), year: number, isbn: cookbookField(isbn),
                                 coverPath: uploadedCoverPath ?? coverPath, notes: cookbookField(notes))
            try await store.saveCookbook(value, existing: book != nil)
            dismiss()
        } catch let failure as CookbookError {
            error = failure.localizedDescription
        } catch {
            self.error = "Das Buch konnte nicht gesichert werden."
        }
    }

    private func lookup() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let url = Backend.site.appending(path: "api/isbn").appending(queryItems: [
                URLQueryItem(name: "isbn", value: normalizedISBN)
            ])
            var request = URLRequest(url: url, timeoutInterval: 25)
            let token = try await Backend.client.auth.session.accessToken
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(ISBNResult.self, from: data)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                error = result.error ?? "Die ISBN konnte nicht abgefragt werden."
                return
            }
            title = result.title ?? title
            if let values = result.authors, !values.isEmpty { authors = values.joined(separator: ", ") }
            publisher = result.publisher ?? publisher
            year = result.year.map(String.init) ?? year
            isbn = result.isbn ?? isbn
            lookupSource = result.source == "openlibrary" ? "Open Library" : "Google Books"
        } catch {
            self.error = "Die ISBN konnte nicht abgefragt werden."
        }
    }

    private struct ISBNResult: Decodable {
        let isbn: String?
        let title: String?
        let authors: [String]?
        let publisher: String?
        let year: Int?
        let source: String?
        let error: String?
    }
}

func cookbookField(_ value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
}
