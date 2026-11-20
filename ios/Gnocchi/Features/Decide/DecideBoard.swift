import GnocchiCore
import Supabase
import SwiftUI

struct DecideBoard: View {
    @Environment(HouseholdStore.self) private var household
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: GameSession
    let demo: Bool
    let busy: Bool
    let submit: (DecideValue) async -> Void
    @State private var counts: [String: Int] = [:]
    @State private var out: Set<String> = []
    @State private var strike: String?
    @State private var picks: [Int: String] = [:]
    @State private var index = 0
    @State private var duelIndex = 0
    @State private var pendingSwipe: SwipeDecision?
    @State private var readyVote: DecideValue?

    private struct SwipeDecision: Hashable {
        let id: String
        let value: Int
    }

    private var options: [String] { session.state.options ?? [] }
    private var pairs: [[String]] { session.state.pairs ?? [] }
    private var deck: [String] { session.state.deck ?? [] }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: textSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        Group {
            if let vote = readyVote {
                GameStatusView(game: session.game, title: "Deine Auswahl steht") {
                    Button("Abgeben") { send(vote) }.buttonStyle(.ink)
                }
            } else {
                switch session.state.phase {
                case .deck: swipeDeck
                case .sieb, .finale: exclusions
                case .duell: duels
                case .lose, .loeffel: allocation
                case .jagd: PlateHunt(options: options, recipe: recipe) {
                    readyVote = $0
                    send($0)
                }
                case .zug: TugBoard(pairs: pairs, startedAt: session.updated_at, sessionID: session.id,
                                    memberID: household.household?.memberID, demo: demo, recipe: recipe) {
                    readyVote = $0
                    send($0)
                }
                default: ProgressView()
                }
            }
        }
        .disabled(busy || pendingSwipe != nil)
        .task(id: pendingSwipe) {
            guard let decision = pendingSwipe else { return }
            if !reduceMotion {
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
            }
            guard deck.indices.contains(index), deck[index] == decision.id else {
                pendingSwipe = nil
                return
            }
            counts[decision.id] = decision.value
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pendingSwipe = nil
                index += 1
            }
        }
    }

    private var swipeDeck: some View {
        GameScroll {
            VStack(spacing: 14) {
                if deck.indices.contains(index) {
                    let id = deck[index]
                    VStack(spacing: 6) {
                        Text("\(index + 1) von \(deck.count) Gerichten")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .contentTransition(.numericText())
                        ProgressView(value: Double(index + 1), total: Double(deck.count))
                            .tint(Theme.accent)
                            .accessibilityHidden(true)
                    }
                    SwipeRecipeCard(recipe: recipe(id)) { voteSwipe($0, for: id) }
                        .id(id)
                        .frame(maxWidth: 310)
                        .background {
                            if index + 1 < deck.count {
                                RoundedRectangle(cornerRadius: Theme.radiusCard)
                                    .fill(Theme.well)
                                    .rotationEffect(.degrees(3))
                                    .padding(4)
                                    .offset(y: 5)
                                    .accessibilityHidden(true)
                            }
                        }
                        .offset(swipeExit)
                        .rotationEffect(.degrees(reduceMotion ? 0 : swipeExit.width / 20))
                        .opacity(pendingSwipe == nil || reduceMotion ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: pendingSwipe)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { swipeButtons(id) }
                        VStack(spacing: 8) { swipeButtons(id) }
                    }
                } else {
                    GameHeading(title: "Deine Auswahl steht")
                    Button("Abgeben") { send(.counts(counts)) }.buttonStyle(.ink)
                }
                if index > 0 {
                    Button("Letzte Auswahl zurücknehmen", systemImage: "arrow.uturn.backward") {
                        index -= 1
                        counts[deck[index]] = nil
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder private func swipeButtons(_ id: String) -> some View {
        swipeButton("Heute nicht", symbol: "xmark", tint: Theme.inkSecondary) { voteSwipe(0, for: id) }
        swipeButton("Lust drauf", symbol: "checkmark", tint: Theme.success) { voteSwipe(1, for: id) }
        swipeButton("Unbedingt", symbol: "heart.fill", tint: Theme.accent) { voteSwipe(2, for: id) }
    }

    private func swipeButton(_ label: String, symbol: String, tint: Color, vote: @escaping () -> Void) -> some View {
        Button(action: vote) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.headline).foregroundStyle(tint)
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.card, in: .rect(cornerRadius: Theme.radiusControl))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .strokeBorder(Theme.hairline)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    private var exclusions: some View {
        let final = session.state.phase == .finale
        return GameScroll {
            GameHeading(
                title: final ? "Streich höchstens ein Gericht" : "Worauf hast du keine Lust?",
                detail: final ? nil : "Tippe auf die Gerichte, die du aussortieren möchtest."
            )
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(options, id: \.self) { id in
                    let selected = final ? strike == id : out.contains(id)
                    Button {
                        if final { strike = selected ? nil : id }
                        else if selected { out.remove(id) } else { out.insert(id) }
                    } label: {
                        GameDishTile(recipe: recipe(id), excluded: selected)
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            submitBar {
                send(final ? .object(["strike": strike.map(DecideValue.string) ?? .null])
                     : .object(["out": .array(options.filter { out.contains($0) }.map(DecideValue.string))]))
            }
        }
    }

    private var duels: some View {
        GameScroll {
            GameHeading(title: "Für welches Gericht stimmst du?")
            if pairs.indices.contains(duelIndex) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(pairs.count == 1 ? "Finale" : "Duell \(duelIndex + 1) von \(pairs.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .accessibilityAddTraits(.isHeader)
                    ProgressView(value: Double(duelIndex + 1), total: Double(pairs.count))
                        .tint(Theme.ink)
                        .accessibilityHidden(true)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(pairs[duelIndex], id: \.self) { id in
                            let selected = picks[duelIndex] == id
                            Button {
                                withAnimation(reduceMotion ? nil : Theme.press) { picks[duelIndex] = id }
                            } label: {
                                GameDishTile(recipe: recipe(id), selected: selected)
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    if duelIndex > 0 {
                        Button("Vorheriges Duell", systemImage: "chevron.left") { duelIndex -= 1 }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(minHeight: 44)
                    }
                }
                .id(duelIndex)
                .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            submitBar(title: duelIndex + 1 < pairs.count ? "Nächstes Duell" : "Abgeben",
                      enabled: picks[duelIndex] != nil) {
                if duelIndex + 1 < pairs.count {
                    withAnimation(reduceMotion ? nil : Theme.press) { duelIndex += 1 }
                } else {
                    send(.object(["picks": .array(pairs.indices.compactMap { picks[$0] }.map(DecideValue.string))]))
                }
            }
        }
    }

    private var allocation: some View {
        let wheel = session.state.phase == .lose
        let total = wheel ? Decide.tickets : Decide.spoons
        let cap = wheel ? Decide.tickets : Decide.spoonsPerDish
        let remaining = max(0, total - counts.values.reduce(0, +))
        let unit = wheel ? (remaining == 1 ? "Los" : "Lose") : "Löffel"
        return GameScroll {
            GameHeading(
                title: wheel ? "Verteile deine Lose" : "Verteile deine Löffel",
                detail: wheel ? nil : "Höchstens \(cap) Löffel pro Gericht."
            )
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(options, id: \.self) { id in
                    let count = counts[id, default: 0]
                    let dish = recipe(id)
                    VStack(spacing: 8) {
                        GameDishTile(recipe: dish, metadata: count == 0 ? nil : "\(count) \(wheel ? (count == 1 ? "Los" : "Lose") : "Löffel")")
                            .overlay(alignment: .topTrailing) {
                                if count > 0 {
                                    Label("\(count)", systemImage: wheel ? "ticket.fill" : "spoon.fill")
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(Theme.onInk)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 7)
                                        .background(Theme.ink, in: Capsule())
                                        .padding(8)
                                        .contentTransition(.numericText())
                                        .accessibilityHidden(true)
                                }
                            }
                        HStack(spacing: 0) {
                            allocationButton("minus", label: "Weniger für \(dish?.title ?? "dieses Rezept")",
                                             enabled: count > 0) { counts[id] = count - 1 }
                            Text(count, format: .number)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .contentTransition(.numericText())
                            allocationButton("plus", label: "Mehr für \(dish?.title ?? "dieses Rezept")",
                                             enabled: remaining > 0 && count < cap) { counts[id] = count + 1 }
                        }
                        .background(Theme.card, in: .capsule)
                        .overlay { Capsule().strokeBorder(Theme.hairline).allowsHitTesting(false) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                HStack(spacing: 7) {
                    ForEach(0..<total, id: \.self) { token in
                        Image(systemName: wheel ? "ticket.fill" : "spoon.fill")
                            .foregroundStyle(token < remaining ? Theme.ink : Theme.inkSecondary.opacity(0.22))
                    }
                }
                .font(.body)
                .padding(.top, 8)
                .animation(reduceMotion ? nil : Theme.press, value: remaining)
                .accessibilityHidden(true)
                submitBar(detail: "\(remaining) \(unit) übrig") {
                    send(.object([wheel ? "tickets" : "spoons": .counts(counts)]))
                }
            }
            .background(Theme.paper)
        }
    }

    private func allocationButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : Theme.press, action)
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(enabled ? Theme.ink : Theme.inkSecondary.opacity(0.45))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func submitBar(title: String = "Abgeben", detail: String? = nil, enabled: Bool = true,
                           action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            if let detail {
                Text(detail)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.numericText())
            }
            Button(title, action: action)
                .buttonStyle(.ink)
                .disabled(!enabled)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
    }

    private func voteSwipe(_ value: Int, for id: String) {
        guard pendingSwipe == nil, deck.indices.contains(index), deck[index] == id else { return }
        pendingSwipe = SwipeDecision(id: id, value: value)
    }

    private var swipeExit: CGSize {
        guard let pendingSwipe, !reduceMotion else { return .zero }
        switch pendingSwipe.value {
        case 0: return CGSize(width: -120, height: 0)
        case 2: return CGSize(width: 0, height: -100)
        default: return CGSize(width: 120, height: 0)
        }
    }

    private func recipe(_ id: String) -> Recipe? {
        household.recipes.first { $0.id == id }
    }

    private func send(_ vote: DecideValue) { Task { await submit(vote) } }
}

private struct SwipeRecipeCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recipe: Recipe?
    let vote: (Int) -> Void
    @GestureState private var translation: CGSize = .zero

    var body: some View {
        GameDishTile(recipe: recipe, compact: false)
        .offset(reduceMotion ? .zero : translation)
        .overlay(alignment: .top) {
            if let direction = direction(translation) {
                Label(direction == 0 ? "Heute nicht" : direction == 1 ? "Lust drauf" : "Unbedingt",
                      systemImage: direction == 0 ? "xmark" : "heart")
                    .padding(12).background(.regularMaterial, in: Capsule()).padding(12)
                    .accessibilityHidden(true)
            }
        }
        .gesture(DragGesture(minimumDistance: 12)
            .updating($translation) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard hypot(value.translation.width, value.translation.height) >= 24 else { return }
                if let direction = direction(value.predictedEndTranslation) { vote(direction) }
            })
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: translation == .zero)
        .accessibilityAction(named: "Heute nicht") { vote(0) }
        .accessibilityAction(named: "Lust drauf") { vote(1) }
        .accessibilityAction(named: "Unbedingt") { vote(2) }
    }

    private func direction(_ offset: CGSize) -> Int? {
        if offset.height < -65 && -offset.height > abs(offset.width) { return 2 }
        if abs(offset.width) > 65 && abs(offset.width) >= abs(offset.height) { return offset.width < 0 ? 0 : 1 }
        return nil
    }
}

struct GameScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

struct GameHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.display(26, relativeTo: .title2))
                .tracking(-0.5)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GameStatusView<Actions: View>: View {
    let game: DecideGame
    let title: String
    var detail: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        GameScroll {
            VStack(spacing: 16) {
                Image("game-\(game.rawValue)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 116, height: 116)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(title)
                        .font(Theme.display(28, relativeTo: .title2))
                        .tracking(-0.6)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                actions
            }
            .padding(.top, 24)
            .frame(maxWidth: 350)
            .frame(maxWidth: .infinity)
        }
    }
}

struct GameDishTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recipe: Recipe?
    var metadata: String?
    var selected = false
    var excluded = false
    var compact = true

    var body: some View {
        PhotoCard(
            url: recipe?.imageURL,
            title: recipe?.title ?? "Rezept nicht verfügbar",
            metadata: metadata ?? recipe?.timeMin.map { "\($0) Min." } ?? recipe?.timeText,
            compact: compact
        )
        .overlay {
            if selected || excluded {
                RoundedRectangle(cornerRadius: compact ? Theme.radiusControl : Theme.radiusCard)
                    .strokeBorder(selected ? Theme.success : Theme.accent, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selected || excluded {
                Image(systemName: selected ? "checkmark" : "minus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(selected ? Theme.success : Theme.accent, in: .circle)
                    .padding(8)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .opacity(excluded ? 0.58 : 1)
        .animation(reduceMotion ? nil : Theme.press, value: selected)
        .animation(reduceMotion ? nil : Theme.press, value: excluded)
    }
}

private struct PlateHunt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Plate: Identifiable {
        let id: Int
        let recipeID: String
        let start: TimeInterval
    }

    let options: [String]
    let recipe: (String) -> Recipe?
    let submit: (DecideValue) -> Void
    @State private var started: Date?
    @State private var plates: [Plate] = []
    @State private var caught: Set<Int> = []

    private var spacing: TimeInterval {
        (Double(Decide.huntSeconds) - Decide.huntVisibleSeconds) / Double(max(1, options.count * Decide.huntShows))
    }

    var body: some View {
        if let started {
            TimelineView(.periodic(from: started, by: 0.1)) { context in
                let elapsed = context.date.timeIntervalSince(started)
                let remaining = max(0, Double(Decide.huntSeconds) - elapsed)
                let visible = plates.filter {
                    !caught.contains($0.id) && $0.start <= elapsed && elapsed < $0.start + Decide.huntVisibleSeconds
                }
                let lanes = max(2, Int(ceil(Decide.huntVisibleSeconds / spacing)))
                GameScroll {
                    HStack {
                        Label("\(caught.count) gefangen", systemImage: "fork.knife")
                            .font(.headline)
                            .contentTransition(.numericText())
                        Spacer()
                        Text("\(Int(ceil(remaining))) s")
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                            .accessibilityLabel("Sekunden übrig")
                            .accessibilityValue(String(Int(ceil(remaining))))
                    }
                    .foregroundStyle(Theme.ink)
                    ProgressView(value: remaining, total: Double(Decide.huntSeconds))
                        .tint(Theme.accent)
                        .accessibilityHidden(true)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(0..<lanes, id: \.self) { lane in
                            if let plate = visible.first(where: { $0.id % lanes == lane }) {
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                                        _ = caught.insert(plate.id)
                                    }
                                } label: {
                                    GameDishTile(recipe: recipe(plate.recipeID))
                                }
                                .id(plate.id)
                                .buttonStyle(PressScaleStyle())
                                .transition(.opacity)
                                .accessibilityHint("Dieses Gericht fangen")
                            } else {
                                RoundedRectangle(cornerRadius: Theme.radiusControl)
                                    .fill(Theme.well)
                                    .aspectRatio(0.75, contentMode: .fit)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: visible.map(\.id))
                }
            }
            .task(id: started) {
                do { try await Task.sleep(for: .seconds(Decide.huntSeconds)) } catch { return }
                let scores = plates.filter { caught.contains($0.id) }.reduce(into: [String: Int]()) {
                    $0[$1.recipeID, default: 0] += 1
                }
                submit(.object(["caught": .counts(scores)]))
            }
        } else {
            GameStatusView(
                game: .jagd,
                title: "Bereit für die Tellerjagd?",
                detail: "Du hast \(Decide.huntSeconds) Sekunden. Tippe die Gerichte an, auf die du Lust hast."
            ) {
                Button("Los geht’s") {
                    let order = options.flatMap { id in Array(repeating: id, count: Decide.huntShows) }.shuffled()
                    plates = order.enumerated().map { Plate(id: $0.offset, recipeID: $0.element, start: Double($0.offset) * spacing) }
                    started = .now
                }
                .buttonStyle(.ink)
            }
        }
    }
}

private struct TugBoard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pairs: [[String]]
    let startedAt: Date
    let sessionID: String
    let memberID: String?
    let demo: Bool
    let recipe: (String) -> Recipe?
    let submit: (DecideValue) -> Void
    @State private var offset: TimeInterval?
    @State private var taps: [Int: [Int]] = [:]
    @State private var live: [String: Pull] = [:]
    @State private var pending: Pull?

    private struct Pull: Codable, Sendable {
        let m: String
        let d: Int
        let l: Int
        let r: Int
    }

    private var maximum: Int { Tug.seconds * Tug.maxTapsPerSecond }

    var body: some View {
        Group {
            if let offset {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let elapsed = Int((context.date.timeIntervalSince(startedAt) + offset) * 1000)
                    if case let .running(duel, phase, left) = Tug.timeline(elapsedMs: elapsed, duels: pairs.count),
                       pairs.indices.contains(duel) {
                        GameScroll {
                            VStack(spacing: 8) {
                                Text(pairs.count == 1 ? "Finale" : "Duell \(duel + 1) von \(pairs.count)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.inkSecondary)
                                Text(phaseTitle(phase))
                                    .font(Theme.display(26, relativeTo: .title2))
                                    .foregroundStyle(Theme.ink)
                                    .accessibilityAddTraits(.isHeader)
                                countdown(left, phase: phase)
                            }
                            .frame(maxWidth: .infinity)
                            rope(duel: duel)
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(pairs[duel].enumerated()), id: \.offset) { side, id in
                                    let count = taps[duel]?[side] ?? 0
                                    Button {
                                        var scores = taps[duel] ?? [0, 0]
                                        let now = Int((Date.now.timeIntervalSince(startedAt) + offset) * 1000)
                                        guard case let .running(current, .pull, _) = Tug.timeline(elapsedMs: now, duels: pairs.count),
                                              current == duel, scores[side] < maximum else { return }
                                        scores[side] += 1
                                        taps[duel] = scores
                                        if let memberID { pending = Pull(m: memberID, d: duel, l: scores[0], r: scores[1]) }
                                    } label: {
                                        GameDishTile(recipe: recipe(id), selected: count > 0)
                                            .overlay(alignment: .topTrailing) {
                                                Text(count, format: .number)
                                                    .font(.headline.monospacedDigit())
                                                    .contentTransition(.numericText())
                                                    .foregroundStyle(Theme.ink)
                                                    .padding(.horizontal, 11)
                                                    .padding(.vertical, 7)
                                                    .background(Theme.card, in: .capsule)
                                                    .padding(8)
                                                    .accessibilityHidden(true)
                                                    .allowsHitTesting(false)
                                            }
                                            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: count)
                                    }
                                    .buttonStyle(PressScaleStyle())
                                    .disabled(phase != .pull)
                                    .accessibilityLabel(recipe(id)?.title ?? "Rezept nicht verfügbar")
                                    .accessibilityValue("\(count) Tipps")
                                }
                            }
                            Text("Tippe so oft du kannst auf dein Gericht.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        GameStatusView(game: .zug, title: "Wird ausgewertet") { ProgressView() }
                    }
                }
                .task(id: offset) {
                    let remaining = Double(Tug.duration(duels: pairs.count)) / 1000 - Date.now.timeIntervalSince(startedAt) - offset
                    do { try await Task.sleep(for: .seconds(max(0, remaining))) } catch { return }
                    let scores = pairs.indices.map { index in
                        DecideValue.array((taps[index] ?? [0, 0]).map { .number(Double($0)) })
                    }
                    submit(.object(["taps": .array(scores)]))
                }
            } else {
                GameStatusView(game: .zug, title: "Serverzeit wird abgeglichen") { ProgressView() }
            }
        }
        .task { offset = demo ? 0 : await DecideStore.clockOffset() }
        .task {
            if !demo { await liveScores() }
        }
    }

    private func phaseTitle(_ phase: Tug.Phase) -> String {
        switch phase {
        case .wait, .count: "Gleich geht’s los"
        case .pull: "Jetzt ziehen"
        case .pause: "Pause"
        }
    }

    private func countdown(_ milliseconds: Int, phase: Tug.Phase) -> some View {
        let duration = switch phase {
        case .wait: Tug.leadMs
        case .count: Tug.countMs
        case .pull: Tug.seconds * 1000
        case .pause: Tug.pauseMs
        }
        let seconds = Int(ceil(Double(milliseconds) / 1000))
        return ProgressRing(value: Double(milliseconds) / Double(duration), lineWidth: 4, tint: phase == .pull ? Theme.accent : Theme.ink) {
            Text(seconds, format: .number)
                .font(.title.monospacedDigit().bold())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .frame(width: 62, height: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sekunden übrig")
        .accessibilityValue(String(seconds))
    }

    private func rope(duel: Int) -> some View {
        let team = live.values.filter { $0.d == duel }
        let left = team.reduce(taps[duel]?[0] ?? 0) { $0 + $1.l }
        let right = team.reduce(taps[duel]?[1] ?? 0) { $0 + $1.r }
        let position = Double(right - left) / Double(max(10, left + right))
        return VStack(spacing: 5) {
            HStack {
                Text(left, format: .number)
                Spacer()
                Text(right, format: .number)
            }
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            .contentTransition(.numericText())
            GeometryReader { proxy in
                ZStack {
                    Capsule().fill(Theme.well).frame(height: 7)
                    Rectangle().fill(Theme.inkSecondary.opacity(0.4)).frame(width: 1, height: 18)
                    Circle().fill(Theme.accent).frame(width: 22, height: 22)
                        .offset(x: proxy.size.width * 0.4 * position)
                        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1), value: position)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gesamtstand: links \(left), rechts \(right)")
    }

    private func liveScores() async {
        let client = Backend.client
        let channel = client.channel("ep-zug-\(sessionID)")
        let messages = channel.broadcastStream(event: "taps")
        do {
            try await channel.subscribeWithError()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await message in messages { await accept(message) }
                }
                group.addTask {
                    while !Task.isCancelled {
                        if let score = await takePending() {
                            let fields: JSONObject = ["m": .string(score.m), "d": .integer(score.d),
                                                        "l": .integer(score.l), "r": .integer(score.r)]
                            await channel.broadcast(event: "taps", message: fields)
                        }
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                }
            }
        } catch {
            // The round result still uses the submitted taps.
        }
        await client.removeChannel(channel)
    }

    private func takePending() -> Pull? {
        defer { pending = nil }
        return pending
    }

    private func accept(_ message: JSONObject) {
        let fields = message["payload"]?.objectValue ?? message
        guard let id = fields["m"]?.stringValue, id != memberID,
              let duel = fields["d"]?.intValue, pairs.indices.contains(duel) else { return }
        let left = max(0, min(maximum, fields["l"]?.intValue ?? 0))
        let right = max(0, min(maximum, fields["r"]?.intValue ?? 0))
        live[id] = Pull(m: id, d: duel, l: left, r: right)
    }
}
