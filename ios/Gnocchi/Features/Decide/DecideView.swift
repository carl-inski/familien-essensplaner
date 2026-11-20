import GnocchiCore
import SwiftUI

struct DecideView: View {
    @Environment(HouseholdStore.self) private var household
    @Environment(DecideStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var suggestedSlot: MealSlot? = nil
    @State private var folder: String?
    @State private var exitSession: GameSession?
    @State private var removePlayer: GamePlayer?
    @State private var scheduling = false
    @State private var shuffleFeedback = 0

    private var activeSession: GameSession? {
        guard let session = store.session, session.status == .lobby || session.status == .playing else { return nil }
        return session
    }

    var body: some View {
        Group {
            if let family = household.household {
                Group {
                    if let session = store.session {
                        if session.status == .playing,
                           store.players.contains(where: { $0.id == family.memberID && $0.round_done < session.round }) {
                            DecideBoard(session: session, demo: household.isDemo, busy: store.busy) { vote in
                                exitSession = nil
                                await store.submit(vote, for: session.round, family: family, demo: household.isDemo)
                            }
                            .id("\(session.id)/\(session.round)")
                        } else {
                            room(session, family: family)
                        }
                    } else {
                        games(family)
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { gesture in
                    guard gesture.startLocation.x <= 20, gesture.translation.width > 72,
                          gesture.translation.width > abs(gesture.translation.height) * 1.7 else { return }
                    requestBack(family, confirm: false)
                })
                .navigationBarBackButtonHidden(activeSession != nil)
                .toolbar {
                    if activeSession != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            backButton(for: family)
                        }
                    }
                }
                .task(id: exitSession?.id) {
                    guard exitSession != nil else { return }
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    exitSession = nil
                }
                .onChange(of: activeSession?.id) {
                    if exitSession?.id != activeSession?.id {
                        exitSession = nil
                    }
                }
                .confirmationDialog("Ohne diese Person weiterspielen?", isPresented: Binding(
                    get: { removePlayer != nil }, set: { if !$0 { removePlayer = nil } }
                ), presenting: removePlayer) { player in
                    Button("Ohne \(name(player.id)) weiterspielen", role: .destructive) {
                        Task { await store.removePlayer(player.id, family: family, demo: household.isDemo) }
                    }
                }
                .sheet(isPresented: $scheduling) {
                    if let session = store.session,
                       let winner = household.recipes.first(where: { $0.id == session.winner_recipe_id }) {
                        NavigationStack {
                            RecipeScheduleView(
                                recipe: winner, initialDay: session.suggested_date,
                                meal: session.suggested_meal ?? .dinner, title: "In die Woche einplanen",
                                onSchedule: { _, slot, expected in
                                    let saved = await store.schedule(slot, expected: expected, family: family, household: household)
                                    defer { store.error = nil }
                                    return saved ? nil : store.error ?? "Das Gericht konnte nicht eingeplant werden."
                                }
                            )
                        }
                        .presentationDetents(RecipeScheduleView.detents(choosesRecipe: false))
                        .presentationContentInteraction(.resizes)
                        .presentationDragIndicator(.visible)
                    }
                }
            }
        }
        .navigationTitle(store.session?.game.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.session == nil {
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .topBarLeading) { gamesTitle }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { gamesTitle }
                }
            }
        }
        .gnScreen()
        .alert("Spielen", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func backButton(for family: Membership) -> some View {
        let armed = exitSession != nil
        let title = exitSession?.created_by == family.memberID ? "Runde abbrechen" : "Runde verlassen"
        return Button {
            requestBack(family)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: armed ? "xmark" : "chevron.left")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                if armed {
                    Text(title).font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(armed ? Color.red : Theme.ink)
        }
        .animation(reduceMotion ? nil : Theme.spring, value: armed)
        .disabled(store.busy)
        .accessibilityLabel(armed ? title : "Zurück")
        .accessibilityHint(armed ? "Erneut tippen, um zu bestätigen" : "")
    }

    private func requestBack(_ family: Membership, confirm: Bool = true) {
        guard !store.busy, let session = activeSession else { return }
        if session.status == .lobby || (confirm && exitSession?.id == session.id) {
            exitSession = nil
            Task { await store.exit(session, family: family, demo: household.isDemo) }
        } else {
            exitSession = session
        }
    }

    private var gamesTitle: some View {
        Text("Spielen")
            .font(Theme.display(28))
            .tracking(-0.6)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader)
    }

    private func games(_ family: Membership) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
                            count: textSize.isAccessibilitySize ? 1 : 2)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let slot = suggestedSlot {
                    Label("\(dayLabel(slot.date)) · \(slot.meal.label)", systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
                if !household.folders.isEmpty {
                    Picker("Rezepte", selection: $folder) {
                        Text("Alle Rezepte").tag(nil as String?)
                        ForEach(household.folders) { Text($0.label).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 8)
                    .background(Theme.card, in: .capsule)
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(DecideGame.allCases) { game in
                        Button {
                            Task {
                                await store.create(game: game, family: family, recipes: household.recipes,
                                                   folder: folder, slot: suggestedSlot, demo: household.isDemo)
                            }
                        } label: {
                            GameTile(game: game)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 2)
            .padding(.bottom, Theme.gutter)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .disabled(store.busy)
    }

    @ViewBuilder
    private func room(_ session: GameSession, family: Membership) -> some View {
        let joined = store.players.contains { $0.id == family.memberID }
        Group {
            switch session.status {
            case .lobby:
                GameStatusView(game: session.game, title: "Warteraum", detail: session.game.detail) {
                    playerList(family: family) { player in
                        player.id == session.created_by
                            ? ("Runde eröffnet", "person.crop.circle.badge.checkmark", Theme.ink)
                            : ("Dabei", "checkmark.circle.fill", Theme.success)
                    }
                    if joined {
                        Button(store.players.count == 1 ? "Allein spielen" : "Spiel starten", systemImage: "play.fill") {
                            Task { await store.start(family: family, demo: household.isDemo) }
                        }
                        .buttonStyle(.ink)
                    }
                    if !joined {
                        Button("Mitspielen", systemImage: "person.badge.plus") {
                            Task { await store.setJoined(true, family: family, demo: household.isDemo) }
                        }
                        .buttonStyle(.ink)
                    } else if session.created_by != family.memberID {
                        Button("Runde verlassen") {
                            requestBack(family)
                        }
                        .buttonStyle(.soft)
                    }
                    lobbyRecipes(session, family: family)
                }
            case .playing:
                waitingRoom(session, family: family, joined: joined)
            case .done:
                GameResultReveal(session: session, recipes: household.recipes, shared: store.players.count > 1) {
                    result(session)
                }
                .id(session.id)
            case .cancelled:
                GameStatusView(game: session.game, title: "Runde abgebrochen") {
                    Button("Neue Runde") { store.closeResult() }.buttonStyle(.ink)
                }
            }
        }
        .disabled(store.busy)
    }

    private func waitingRoom(_ session: GameSession, family: Membership, joined: Bool) -> some View {
        let waiting = store.players.filter { $0.round_done < session.round }
        let otherWaiting = waiting.filter { $0.id != family.memberID }
        let title = if !joined { "Du schaust zu" } else if waiting.isEmpty { "Alle fertig" } else { "Stimme abgegeben" }
        let detail: String? = if !joined {
            nil
        } else if waiting.isEmpty {
            "Die Stimmen werden ausgewertet."
        } else {
            "Es geht weiter, sobald alle fertig sind."
        }
        return GameStatusView(game: session.game, title: title, detail: detail) {
            playerList(family: family) { player in
                player.round_done >= session.round
                    ? ("Fertig", "checkmark.circle.fill", Theme.success)
                    : ("Spielt noch", "clock", Theme.inkSecondary)
            }
            if joined, !otherWaiting.isEmpty {
                DisclosureGroup("Jemand ist weg?") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(otherWaiting) { player in
                            Button("Ohne \(name(player.id)) weiterspielen", role: .destructive) { removePlayer = player }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
                .gnCard(padding: 16)
            }
        }
    }

    @ViewBuilder private func lobbyRecipes(_ session: GameSession, family: Membership) -> some View {
        let recipes = session.candidates.compactMap { id in household.recipes.first { $0.id == id } }
        let canShuffle = session.created_by == family.memberID
        let width: CGFloat = textSize.isAccessibilitySize ? 200 : 126
        if canShuffle || !recipes.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("Gerichte in dieser Runde")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        if canShuffle {
                            Button {
                                shuffleFeedback += 1
                                Task {
                                    await store.reshuffle(family: family, recipes: household.recipes, demo: household.isDemo)
                                }
                            } label: {
                                reshuffleTile
                            }
                            .buttonStyle(PressScaleStyle())
                            .frame(width: width)
                            .disabled(store.busy || store.shuffling)
                            .accessibilityLabel(store.shuffling ? "Gerichte werden gemischt" : "Neu mischen")
                        }
                        ForEach(recipes) { recipe in
                            PhotoCard(url: recipe.imageURL, title: recipe.title,
                                      aspectRatio: 126.0 / 160.0, compact: true)
                                .frame(width: width)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .animation(reduceMotion ? nil : Theme.spring, value: session.candidates)
            }
        }
    }

    private var reshuffleTile: some View {
        Color.clear
            .aspectRatio(126.0 / 160.0, contentMode: .fit)
            .overlay {
                VStack(spacing: 9) {
                    shuffleSymbol
                    Text(store.shuffling ? "Wird gemischt …" : "Neu mischen")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(8)
                .foregroundStyle(store.busy || store.shuffling ? Theme.inkSecondary : Theme.ink)
            }
            .background(Theme.card, in: .rect(cornerRadius: Theme.radiusControl))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .strokeBorder(Theme.hairline)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: Theme.radiusControl))
    }

    @ViewBuilder private var shuffleSymbol: some View {
        let icon = Image(systemName: "shuffle").font(.title2.weight(.semibold))
        if reduceMotion {
            icon
        } else {
            icon.phaseAnimator([0.0, -13.0, 13.0, 0.0], trigger: shuffleFeedback) { symbol, angle in
                symbol.rotationEffect(.degrees(angle))
            } animation: { _ in .easeInOut(duration: 0.09) }
        }
    }

    private func playerList(
        family: Membership,
        status: @escaping (GamePlayer) -> (text: String, symbol: String, tint: Color)
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Teilnehmende")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if store.players.isEmpty {
                Text("Noch niemand dabei")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            ForEach(store.players) { player in
                let member = household.members.first { $0.id == player.id }
                let person = member?.name ?? name(player.id)
                let state = status(player)
                Divider().accessibilityHidden(true)
                HStack(spacing: 10) {
                    if let member {
                        MealMemberAvatar(member: member, size: 40)
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 40, height: 40)
                            .background(Theme.well, in: .circle)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.id == family.memberID ? "\(person) (du)" : person)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(state.text)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: state.symbol)
                        .font(.body.weight(.medium))
                        .foregroundStyle(state.tint)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gnCard(padding: 16)
    }

    private func result(_ session: GameSession) -> some View {
        GameScroll {
            GameHeading(title: "Entschieden", detail: resultDetail(session.state.reveal))
            if let reveal = session.state.reveal, reveal.kind == "rad",
               let options = reveal.options, let weights = reveal.weights, let winner = session.winner_recipe_id {
                DisclosureGroup("Das Losergebnis") {
                    WheelResult(options: options, weights: weights, winner: winner, title: { id in
                        household.recipes.first { $0.id == id }?.title ?? "Rezept nicht verfügbar"
                    }, animateSpin: false)
                }
                .font(.subheadline.weight(.medium))
                .gnCard(padding: 16)
            }
            if let recipe = household.recipes.first(where: { $0.id == session.winner_recipe_id }) {
                NavigationLink {
                    RecipeDetailView(recipe: recipe)
                } label: {
                    GameDishTile(recipe: recipe, compact: false)
                        .frame(maxWidth: 280)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityHint("Öffnet das Rezept")
                if let date = session.date {
                    Label("Eingeplant · \(dayLabel(date)) · \(session.meal?.label ?? "")", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gnCard(padding: 16)
                } else {
                    Button("In die Woche einplanen", systemImage: "calendar.badge.plus") { scheduling = true }
                        .buttonStyle(.ink)
                }
            } else {
                Text("Das Gewinnerrezept ist nicht mehr verfügbar.")
                    .foregroundStyle(Theme.inkSecondary)
            }
            Button("Neue Runde") { store.closeResult() }
                .buttonStyle(.soft)
            if let reveal = session.state.reveal, let winner = session.winner_recipe_id {
                scoreSection(reveal, winner: winner)
            }
        }
    }

    private func resultDetail(_ reveal: DecideState.Reveal?) -> String? {
        let shared = store.players.count > 1
        switch reveal?.kind {
        case "match": return shared ? "Darauf haben alle Lust." : "Darauf hast du Lust."
        case "finale": return "Im Stechen ausgewählt."
        case "einzig": return "Ein Gericht ist übrig geblieben."
        case "duell": return "Turniersieger"
        case "rad": return "Das Rad hat entschieden."
        case "zug": return reveal?.taps.map { "Im Finale wurde \($0) Mal getippt." }
        default: return nil
        }
    }

    @ViewBuilder
    private func scoreSection(_ reveal: DecideState.Reveal, winner: String) -> some View {
        if reveal.kind == "loeffel" || reveal.kind == "jagd",
           let options = reveal.options, let totals = reveal.totals, let minima = reveal.mins,
           !options.isEmpty, options.count == totals.count, options.count == minima.count {
            let maxScore = Double(max(1, totals.max() ?? 0))
            VStack(alignment: .leading, spacing: 14) {
                Text(reveal.kind == "loeffel" ? "Verteilte Löffel" : "Gefangene Teller")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                ForEach(options.indices, id: \.self) { index in
                    let id = options[index]
                    let recipe = household.recipes.first { $0.id == id }
                    let title = recipe?.title ?? "Rezept nicht verfügbar"
                    let won = id == winner
                    HStack(spacing: 10) {
                        if let recipe {
                            RecipeThumbnail(recipe: recipe)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent {
                                Text(totals[index], format: .number).monospacedDigit()
                            } label: {
                                if won {
                                    Label(title, systemImage: "trophy.fill")
                                        .fontWeight(.semibold)
                                        .accessibilityLabel("\(title), gewonnen")
                                } else {
                                    Text(title)
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            ProgressView(value: Double(max(0, totals[index])), total: maxScore)
                                .tint(won ? Theme.accent : Theme.inkSecondary)
                                .accessibilityHidden(true)
                            if store.players.count > 1 {
                                Text(minima[index] > 0 ? "Von allen" : "Nicht von allen")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .gnCard(padding: 16)
        }
    }

    private func name(_ id: String) -> String {
        household.members.first(where: { $0.id == id })?.name ?? "Familienmitglied"
    }

    private func dayLabel(_ key: String) -> String {
        guard let date = BerlinDay.date(for: key) else { return key }
        var style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "de_DE"))
        style.timeZone = BerlinDay.calendar.timeZone
        return date.formatted(style)
    }
}

private struct GameResultReveal<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: GameSession
    let recipes: [Recipe]
    let shared: Bool
    @ViewBuilder let content: Content
    @State private var revealed = false
    @State private var settling = false

    private var canSpinWheel: Bool {
        guard let reveal = session.state.reveal, reveal.kind == "rad",
              let options = reveal.options, let weights = reveal.weights,
              !options.isEmpty, options.count == weights.count,
              let winner = session.winner_recipe_id else { return false }
        return options.contains(winner)
    }

    var body: some View {
        Group {
            if revealed || reduceMotion {
                content.transition(.opacity)
            } else {
                GameScroll {
                    VStack(spacing: 18) {
                        if canSpinWheel, let reveal = session.state.reveal,
                           let options = reveal.options, let weights = reveal.weights,
                           let winner = session.winner_recipe_id {
                            GameHeading(title: "Das Rad dreht sich")
                            WheelResult(options: options, weights: weights, winner: winner, title: { id in
                                recipes.first { $0.id == id }?.title ?? "Rezept nicht verfügbar"
                            }, onReveal: revealResult)
                            .gnCard(padding: 18)
                        } else {
                            Image("game-\(session.game.rawValue)")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .rotationEffect(.degrees(settling ? 0 : -9))
                                .scaleEffect(settling ? 1 : 0.84)
                                .opacity(settling ? 1 : 0.45)
                                .accessibilityHidden(true)
                            Text(shared ? "Eure Wahl" : "Deine Wahl")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
                .transition(.opacity)
            }
        }
        .task {
            guard !reduceMotion, !revealed, !canSpinWheel else { return }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.84)) { settling = true }
            do { try await Task.sleep(for: .milliseconds(620)) }
            catch { return }
            revealResult()
        }
    }

    private func revealResult() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { revealed = true }
    }
}

private struct GameTile: View {
    let game: DecideGame

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.aspectRatio(0.80, contentMode: .fit)
                .overlay(alignment: .top) {
                    GeometryReader { geometry in
                        Image("game-\(game.rawValue)")
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width * 0.60, height: geometry.size.height * 0.50)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 9)
                    }
                    .accessibilityHidden(true)
                }
            VStack(spacing: 3) {
                Text(game.title).font(.headline).foregroundStyle(Theme.ink)
                Text(game.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.bottom, 13)
            .padding(.top, 104)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [Theme.well.opacity(0.78), Theme.card, Theme.card],
                           startPoint: .topLeading, endPoint: .bottom)
        }
        .clipShape(.rect(cornerRadius: Theme.radiusCard))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(Theme.hairline)
                .allowsHitTesting(false)
        }
        .contentShape(.rect(cornerRadius: Theme.radiusCard))
        .accessibilityElement(children: .combine)
    }
}

extension DecideGame {
    var title: String {
        switch self {
        case .swipe: "Swipen"
        case .duell: "Duell"
        case .rad: "Glücksrad"
        case .loeffel: "Löffel"
        case .jagd: "Tellerjagd"
        case .zug: "Tauziehen"
        }
    }

    var symbol: String {
        switch self {
        case .swipe: "hand.draw"
        case .duell: "rectangle.split.2x1"
        case .rad: "circle.dotted.circle"
        case .loeffel: "fork.knife"
        case .jagd: "takeoutbag.and.cup.and.straw"
        case .zug: "arrow.left.and.right"
        }
    }

    var detail: String {
        switch self {
        case .swipe: "Findet ein Gericht, auf das alle Lust haben."
        case .duell: "Zwei Gerichte treten gegeneinander an."
        case .rad: "Verteilt eure Lose und lasst das Rad entscheiden."
        case .loeffel: "Verteilt Löffel für eure Favoriten."
        case .jagd: "Fangt die Teller, die euch schmecken."
        case .zug: "Tippt so schnell ihr könnt für euer Gericht."
        }
    }
}
