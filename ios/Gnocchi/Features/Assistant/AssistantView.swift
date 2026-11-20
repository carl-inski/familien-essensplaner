import GnocchiCore
import PhotosUI
import Supabase
import SwiftUI

@MainActor
@Observable
final class AssistantDraft {
    fileprivate var prompt = ""
    fileprivate var photos: [AssistantAttachment] = []
}

struct AssistantView: View {
    @Environment(HouseholdStore.self) private var household
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .subheadline) private var suggestionWidth = 212.0
    let store: AssistantStore
    let recipe: Recipe?
    let accountEmail: String?
    @State private var draft: AssistantDraft
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoError: String?
    @State private var editing: RecipeDraft?
    @State private var openedRecipe: Recipe?
    @State private var confirmClear = false
    @FocusState private var composing: Bool

    init(store: AssistantStore, recipe: Recipe? = nil, accountEmail: String? = nil, draft: AssistantDraft? = nil) {
        self.store = store
        self.recipe = recipe
        self.accountEmail = accountEmail
        self._draft = State(initialValue: draft ?? AssistantDraft())
    }

    private var available: Bool { store.status?.enabled != false || store.busy }
    private var canSend: Bool {
        !store.applying && selectedPhotos.isEmpty
            && (!draft.photos.isEmpty || !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private var remainingPhotoCount: Int { AssistantStore.maximumPhotoCount - draft.photos.count }

    var body: some View {
        ScrollViewReader { anchor in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !available {
                        ContentUnavailableView {
                            Label("KI noch nicht eingerichtet", systemImage: "sparkles")
                        } description: {
                            if let reason = store.status?.reason { Text(reason) }
                        } actions: {
                            Button("Erneut prüfen") { Task { await refreshStatus() } }
                        }
                    } else if store.messages.isEmpty {
                        welcome
                    }
                    ForEach(store.messages) { message in
                        messageView(message)
                    }
                    if store.busy {
                        ProgressView("Antwort wird geladen").font(.subheadline)
                    }
                    if let error = store.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.circle")
                            Button("Erneut versuchen") { Task { await store.retry(recipe: recipe, demo: household.isDemo) } }
                        }
                    }
                    if recipe == nil, let slot = store.pendingMealQuestion {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(AssistantStore.mealQuestionLabel(slot), systemImage: "calendar")
                            ViewThatFits {
                                HStack { mealQuestionButtons(slot) }
                                VStack(alignment: .leading) { mealQuestionButtons(slot) }
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("latest")
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refreshStatus() }
            .onChange(of: store.messages.count) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { anchor.scrollTo("latest", anchor: .bottom) }
            }
            .onChange(of: store.busy) {
                if !store.busy { anchor.scrollTo("latest", anchor: .bottom) }
            }
            .onChange(of: store.pendingMealQuestion) {
                if store.pendingMealQuestion != nil { anchor.scrollTo("latest", anchor: .bottom) }
            }
        }
        .background { chatBackground }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if available, store.showsComposer {
                VStack(spacing: 8) {
                    if store.messages.isEmpty, !store.busy, !composing,
                       recipe == nil, store.pendingMealQuestion == nil {
                        suggestions
                    }
                    composer
                }
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Assistent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await refreshStatus() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !store.messages.isEmpty {
                    Button("Neuer Chat", systemImage: "square.and.pencil") { confirmClear = true }
                        .disabled(store.busy || store.applying)
                }
                if let accountEmail { AccountToolbarLink(email: accountEmail) }
            }
        }
        .confirmationDialog("Neuen Chat beginnen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Verlauf löschen", role: .destructive) { store.clear() }
        }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let editing {
                NavigationStack { RecipeEditor(imported: editing) }.presentationDragIndicator(.visible)
            }
        }
        .navigationDestination(isPresented: Binding(get: { openedRecipe != nil }, set: { if !$0 { openedRecipe = nil } })) {
            if let openedRecipe { RecipeDetailView(recipe: openedRecipe) }
        }
        .environment(\.openURL, OpenURLAction { url in
            let isInternal = url.host == nil || url.host == Backend.site.host
            let segments = url.path.split(separator: "/")
            if isInternal, segments.count == 2, segments[0] == "rezepte",
               let recipe = household.recipes.first(where: { $0.id == segments[1] }) {
                openedRecipe = recipe
                return .handled
            }
            return ["https", "http"].contains(url.scheme) ? .systemAction : .discarded
        })
        .task(id: selectedPhotos) { await loadPhotos(selectedPhotos) }
    }

    private var chatBackground: some View {
        ZStack {
            Theme.paper
            if !reduceTransparency {
                RadialGradient(colors: [Theme.accent.opacity(0.10), .clear],
                               center: .top, startRadius: 20, endRadius: 380)
            }
        }
        .ignoresSafeArea()
    }

    private var welcome: some View {
        let name = household.members.first { $0.id == household.household?.memberID }?.name
        let greeting = name.map { "Was kochen wir, \($0)?" } ?? "Was kochen wir?"
        return VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 78, height: 78)
                .background(Theme.assistantButton, in: .circle)
                .accessibilityHidden(true)
            if recipe == nil {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text(recipe == nil ? greeting : "Frag mich zu diesem Rezept")
                .font(Theme.display(28, relativeTo: .title))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .tracking(-0.5)
                .accessibilityAddTraits(.isHeader)
            if let recipe {
                Text(recipe.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.top, 25)
        .frame(maxWidth: .infinity)
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                suggestion("Woche planen", detail: "Gerichte für die nächsten Tage", asset: "week",
                           prompt: "Was kochen wir diese Woche?")
                suggestion("Wieder kochen", detail: "Lange nicht gegessene Rezepte", asset: "pot",
                           prompt: "Was haben wir lange nicht gegessen?")
                suggestion("Einkauf ansehen", detail: "Was wir noch brauchen", asset: "basket",
                           prompt: "Was steht auf der Einkaufsliste?")
            }
            .padding(.horizontal, Theme.gutter)
        }
        .scrollIndicators(.hidden)
    }

    private func suggestion(_ title: String, detail: String, asset: String, prompt: String) -> some View {
        Button { send(prompt) } label: {
            HStack(spacing: 9) {
                Image("assistant-\(asset)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 35, height: 35)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(textSize.isAccessibilitySize ? 2 : 1, reservesSpace: true)
                    Text(detail).font(.caption).foregroundStyle(Theme.inkSecondary)
                        .lineLimit(2, reservesSpace: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .frame(width: suggestionWidth, alignment: .leading)
            .background(Theme.card.opacity(reduceTransparency ? 1 : 0.87),
                        in: .rect(cornerRadius: Theme.radiusControl))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.hairline)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(PressScaleStyle())
    }

    @ViewBuilder private func mealQuestionButtons(_ slot: MealSlot) -> some View {
        Button("Vorschlag anfragen") {
            Task { await store.askAboutMeal(slot, demo: household.isDemo, recipes: household.recipes) }
        }
            .buttonStyle(.bordered)
            .disabled(!store.canAskAboutMeal)
        Button("Verwerfen") { store.pendingMealQuestion = nil }
            .buttonStyle(.borderless)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Frag Gnocchi …", text: $draft.prompt, axis: .vertical)
                .lineLimit(1...5)
                .focused($composing)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
            if let photoError {
                Label(photoError, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: max(1, remainingPhotoCount),
                             selectionBehavior: .ordered, matching: .images) {
                    AssistantComposerIcon(label: "Foto anhängen", systemImage: "plus", primary: false)
                }
                .buttonStyle(.plain)
                .disabled(store.busy || !selectedPhotos.isEmpty || remainingPhotoCount == 0)
                .accessibilityValue("\(draft.photos.count) von \(AssistantStore.maximumPhotoCount) Fotos angehängt")
                if draft.photos.isEmpty && selectedPhotos.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    photoStrip
                }
                if store.busy {
                    Button { store.stop() } label: {
                        AssistantComposerIcon(label: "Antwort stoppen", systemImage: "stop.fill", primary: true)
                    }
                    .buttonStyle(PressScaleStyle())
                } else {
                    Button { send(draft.prompt) } label: {
                        AssistantComposerIcon(label: "Senden", systemImage: "arrow.up", primary: true)
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.48)
                }
            }
        }
        .padding(12)
        .background(Theme.card.opacity(reduceTransparency ? 1 : 0.92),
                    in: .rect(cornerRadius: Theme.radiusCard))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.hairline)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.09), radius: 16, y: 8)
        .frame(maxWidth: 640)
        .padding(.horizontal, Theme.gutter)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(draft.photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        draft.photos.removeAll { $0.id == photo.id }
                        photoError = nil
                    } label: {
                        if let thumbnail = UIImage(data: photo.jpeg) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(.rect(cornerRadius: 9))
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.8))
                                        .padding(1)
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Foto \(index + 1) entfernen")
                }
                if !selectedPhotos.isEmpty {
                    ProgressView().frame(width: 44, height: 44)
                        .accessibilityLabel("Fotos werden geladen")
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 44)
    }

    @ViewBuilder private func messageView(_ message: AssistantMessage) -> some View {
        ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
            if let text = part["text"]?.stringValue, !text.isEmpty {
                if message.role == "user" {
                    Text(text).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.13), in: .rect(cornerRadius: 18))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    let formatted = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                    Text(formatted ?? AttributedString(text)).textSelection(.enabled)
                }
            } else if part["type"]?.stringValue == "file", message.role == "user" {
                Label("Foto gesendet", systemImage: "photo").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if let tool = AssistantTool(part: part), let id = part["toolCallId"]?.stringValue {
                if part["state"]?.stringValue == "input-available" {
                    AssistantProposal(tool: tool, input: part["input"]?.objectValue ?? [:],
                                      isBusy: store.busy || store.applying, loadPreview: {
                        try await store.preview(id: id, household: household)
                    }) { accepted, selectedInput in
                        Task {
                            await store.respond(id: id, approve: accepted, household: household, recipe: recipe,
                                                selectedInput: selectedInput, openDraft: { editing = $0 })
                        }
                    }
                    .id(id)
                } else if let output = part["output"]?.objectValue, let title = output["meldung"]?.stringValue {
                    Label(title, systemImage: output["ok"] == .bool(true) ? "checkmark.circle" : "minus.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func send(_ text: String) {
        guard !store.busy, !store.applying, selectedPhotos.isEmpty else { return }
        let attachments = draft.photos.map(\.jpeg)
        guard !attachments.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        composing = false
        draft.prompt = ""
        draft.photos = []
        photoError = nil
        Task { await store.send(text, photos: attachments, recipe: recipe, demo: household.isDemo) }
    }

    private func loadPhotos(_ selection: [PhotosPickerItem]) async {
        guard !selection.isEmpty else { return }
        photoError = nil
        var loaded: [AssistantAttachment] = []
        var failures = 0
        for item in selection.prefix(remainingPhotoCount) {
            do {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failures += 1
                    continue
                }
                try Task.checkCancellation()
                if let jpeg = Self.preparePhoto(data) {
                    loaded.append(AssistantAttachment(jpeg: jpeg))
                } else {
                    failures += 1
                }
            } catch is CancellationError {
                return
            } catch {
                failures += 1
            }
        }
        guard !Task.isCancelled else { return }
        draft.photos.append(contentsOf: loaded)
        selectedPhotos = []
        if failures > 0 {
            photoError = failures == 1 ? "Ein Foto konnte nicht geladen werden." : "\(failures) Fotos konnten nicht geladen werden."
        }
    }

    private static func preparePhoto(_ data: Data) -> Data? {
        for size in [1_400, 1_100, 850, 640] {
            guard let jpeg = RecipePhoto.jpeg(from: data, maxPixelSize: size) else { return nil }
            if jpeg.count <= AssistantStore.maximumPhotoBytes { return jpeg }
        }
        return nil
    }

    private func refreshStatus() async {
        try? await store.refreshStatus(demo: household.isDemo)
    }
}

fileprivate struct AssistantAttachment: Identifiable {
    let id = UUID()
    let jpeg: Data
}

private struct AssistantComposerIcon: View {
    let label: String
    let systemImage: String
    let primary: Bool

    var body: some View {
        Label(label, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(primary ? Theme.onInk : Theme.ink)
            .frame(width: 44, height: 44)
            .background(primary ? Theme.ink : Theme.well, in: .circle)
    }
}

private struct AssistantProposal: View {
    let tool: AssistantTool
    let input: JSONObject
    let isBusy: Bool
    let loadPreview: () async throws -> AssistantPreview
    let decide: (Bool, JSONObject?) -> Void
    @State private var preview: AssistantPreview?
    @State private var failed: String?
    @State private var selected: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(tool.title, systemImage: "sparkles").font(.headline).accessibilityAddTraits(.isHeader)
            if let failed {
                Text(failed).foregroundStyle(.secondary)
            } else if let preview {
                ForEach(Array(preview.lines.enumerated()), id: \.offset) { index, line in
                    if tool == .batch {
                        Toggle(line, isOn: Binding(get: { selected.contains(index) }, set: {
                            if $0 { selected.insert(index) } else { selected.remove(index) }
                        }))
                    } else { Text(line) }
                }
                ViewThatFits {
                    HStack { buttons }
                    VStack(alignment: .leading) { buttons }
                }
            } else {
                ProgressView("Vorschlag wird geprüft")
            }
            if failed != nil {
                Button("Verwerfen") { decide(false, nil) }.disabled(isBusy)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 19))
        .task {
            do {
                let loaded = try await loadPreview()
                if !Task.isCancelled {
                    preview = loaded
                    selected = Set(loaded.lines.indices)
                }
            } catch {
                if !Task.isCancelled { failed = (error as? AssistantFailure)?.errorDescription ?? "Vorschlag konnte nicht geprüft werden." }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        Button("Verwerfen") { decide(false, nil) }.buttonStyle(.bordered).disabled(isBusy)
        Button(tool == .recipe ? "Im Formular öffnen" : "Übernehmen", role: tool == .remove ? .destructive : nil) {
            if tool == .batch {
                let rows = input["eintraege"]?.arrayValue ?? []
                decide(true, ["eintraege": .array(rows.enumerated().compactMap { selected.contains($0.offset) ? $0.element : nil })])
            } else { decide(true, nil) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy || (tool == .batch && selected.isEmpty))
    }
}
