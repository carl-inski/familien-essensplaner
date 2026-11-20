import SwiftUI

/// Antworten aus dem Onboarding. Bleiben auf dem Gerät und passen nur Texte an.
struct OnboardingAnswers: Equatable {
    enum Household: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: Self { self }
        var title: String {
            switch self {
            case .small: "1 bis 2"
            case .medium: "3 bis 4"
            case .large: "5 oder mehr"
            }
        }
        var detail: String {
            switch self {
            case .small: "Kleiner Tisch"
            case .medium: "Familientisch"
            case .large: "Lange Tafel"
            }
        }
        var symbol: String {
            switch self {
            case .small: "person.2"
            case .medium: "person.3"
            case .large: "person.3.sequence"
            }
        }
        /// Rechenwert für die Zusammenfassung.
        var people: Int {
            switch self {
            case .small: 2
            case .medium: 4
            case .large: 5
            }
        }
    }

    enum Pain: String, CaseIterable, Identifiable {
        case deciding, attendance, shopping, repetition
        var id: Self { self }
        var title: String {
            switch self {
            case .deciding: "Was kochen wir heute?"
            case .attendance: "Wer isst überhaupt mit?"
            case .shopping: "Doppelt gekauft, Hälfte vergessen"
            case .repetition: "Immer dieselben fünf Gerichte"
            }
        }
        var symbol: String {
            switch self {
            case .deciding: "questionmark.bubble"
            case .attendance: "person.crop.circle.badge.questionmark"
            case .shopping: "cart.badge.questionmark"
            case .repetition: "arrow.triangle.2.circlepath"
            }
        }
        /// Was Gnocchi dagegen tut.
        var answer: String {
            switch self {
            case .deciding: "Vorschläge und Spiele entscheiden für euch."
            case .attendance: "Jede Person sagt selbst, ob sie mitisst."
            case .shopping: "Eine Liste für alle, abgehakt ist abgehakt."
            case .repetition: "Gnocchi erinnert an Gerichte, die lange nicht dran waren."
            }
        }
    }

    enum Rhythm: String, CaseIterable, Identifiable {
        case few, some, daily
        var id: Self { self }
        var title: String {
            switch self {
            case .few: "2 bis 3 Mal"
            case .some: "4 bis 5 Mal"
            case .daily: "Fast jeden Tag"
            }
        }
        var detail: String {
            switch self {
            case .few: "Der Rest ergibt sich"
            case .some: "Unter der Woche wird gekocht"
            case .daily: "Bei uns steht immer ein Topf auf dem Herd"
            }
        }
        var symbol: String {
            switch self {
            case .few: "flame"
            case .some: "frying.pan"
            case .daily: "fork.knife"
            }
        }
        var mealsPerWeek: Int {
            switch self {
            case .few: 3
            case .some: 5
            case .daily: 7
            }
        }
    }

    var household: Household?
    var pains: Set<Pain> = []
    var rhythm: Rhythm?

    /// Portionen pro Woche aus Personen mal Kochtagen. Nil, solange eine Antwort fehlt.
    var portionsPerWeek: Int? {
        guard let household, let rhythm else { return nil }
        return household.people * rhythm.mealsPerWeek
    }
}

/// Merkt sich, ob das Onboarding schon gezeigt wurde.
enum OnboardingState {
    private static let key = "onboardingFinished"
    static var finished: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Erster Start: Begrüßung, drei Fragen, Zusammenfassung, dann Konto.
struct OnboardingFlow: View {
    /// `register`: Konto erstellen, sonst nur anmelden.
    let finish: (_ register: Bool) -> Void

    private enum Step: Int, CaseIterable { case welcome, household, pains, rhythm, summary }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.welcome
    @State private var forward = true
    @State private var answers = OnboardingAnswers()

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                if step != .welcome { header }
                page
                    .id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: 520)
        }
        .animation(Theme.spring, value: step)
    }

    // MARK: Kopf mit Zurück und Fortschritt

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                go(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
            } label: {
                Image(systemName: "arrow.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: .circle)
                    .overlay { Circle().strokeBorder(Theme.hairline) }
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Zurück")

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.well)
                    Capsule().fill(Theme.ink)
                        .frame(width: proxy.size.width * CGFloat(step.rawValue) / CGFloat(Step.allCases.count - 1))
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Schritt \(step.rawValue) von \(Step.allCases.count - 1)")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome:
            WelcomePage(start: { go(to: .household) }, signIn: { complete(register: false) })
        case .household:
            QuestionPage(
                title: "Für wie viele kocht ihr meistens?",
                subtitle: "Gäste und Ausnahmen kommen später mit einem Tipp dazu.",
                canContinue: answers.household != nil,
                next: { go(to: .pains) }
            ) {
                ForEach(OnboardingAnswers.Household.allCases) { option in
                    OptionCard(symbol: option.symbol, title: option.title, detail: option.detail,
                               selected: answers.household == option) { answers.household = option }
                }
            }
        case .pains:
            QuestionPage(
                title: "Was nervt euch beim Essen am meisten?",
                subtitle: "Du kannst mehrere auswählen.",
                canContinue: !answers.pains.isEmpty,
                next: { go(to: .rhythm) }
            ) {
                ForEach(OnboardingAnswers.Pain.allCases) { option in
                    OptionCard(symbol: option.symbol, title: option.title,
                               selected: answers.pains.contains(option)) {
                        if answers.pains.contains(option) { answers.pains.remove(option) }
                        else { answers.pains.insert(option) }
                    }
                }
            }
        case .rhythm:
            QuestionPage(
                title: "Wie oft wird bei euch pro Woche gekocht?",
                subtitle: "Ungefähr reicht. Der Plan passt sich jede Woche an.",
                canContinue: answers.rhythm != nil,
                next: { go(to: .summary) }
            ) {
                ForEach(OnboardingAnswers.Rhythm.allCases) { option in
                    OptionCard(symbol: option.symbol, title: option.title, detail: option.detail,
                               selected: answers.rhythm == option) { answers.rhythm = option }
                }
            }
        case .summary:
            SummaryPage(answers: answers, register: { complete(register: true) }, signIn: { complete(register: false) })
        }
    }

    private func go(to next: Step) {
        forward = next.rawValue > step.rawValue
        step = next
    }

    private func complete(register: Bool) {
        OnboardingState.finished = true
        finish(register)
    }
}

// MARK: - Begrüßung

/// Die Begrüßung zeigt die vier Hauptfunktionen der App.
private struct WelcomePage: View {
    let start: () -> Void
    let signIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var word = 0

    private let words = ["Planen", "Einkaufen", "Kochen", "Entscheiden"]
    private let symbols = ["calendar", "cart.fill", "frying.pan.fill", "dice.fill"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            carousel
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 10) {
                Text("Wer mitisst, bestimmt den Einkauf.")
                    .font(Theme.display(32))
                    .tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Ein Wochenplan für die ganze Familie. Die Liste zeigt immer, was noch fehlt.")
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 22)

            VStack(spacing: 10) {
                Button("Los geht’s", action: start).buttonStyle(.ink)
                Button("Ich habe schon ein Konto", action: signIn).buttonStyle(.soft)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(Theme.spring) { word = (word + 1) % words.count }
            }
        }
    }

    /// Vier Wörter übereinander, das aktive scharf, die anderen blass.
    private var carousel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(words.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    if index == word {
                        Image(systemName: symbols[index])
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(words[index])
                        .font(Theme.display(38))
                        .tracking(-0.8)
                        .foregroundStyle(index == word ? Theme.ink : Theme.ink.opacity(0.13))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel("Planen, einkaufen, kochen, entscheiden")
    }

}

// MARK: - Frage

/// Je Seite eine Frage mit Antwortkarten und einer Weiter-Schaltfläche.
private struct QuestionPage<Options: View>: View {
    let title: String
    let subtitle: String
    let canContinue: Bool
    let next: () -> Void
    @ViewBuilder var options: Options

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(Theme.display(30))
                            .tracking(-0.5)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 10) { options }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button("Weiter", action: next)
                .buttonStyle(.ink)
                .disabled(!canContinue)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Zusammenfassung

/// Letzte Seite: was Gnocchi für diese Familie tut, Schritt für Schritt abgehakt.
private struct SummaryPage: View {
    let answers: OnboardingAnswers
    let register: () -> Void
    let signIn: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0

    private var lines: [(symbol: String, text: String)] {
        var result: [(String, String)] = []
        if let portions = answers.portionsPerWeek {
            result.append(("fork.knife", "Rund \(portions) Portionen pro Woche. Gnocchi rechnet sie für euch aus."))
        }
        let pains = OnboardingAnswers.Pain.allCases.filter(answers.pains.contains)
        result += pains.map { ($0.symbol, $0.answer) }
        if result.count < 3 {
            result.append(("cart", "Ändert sich der Plan, zeigt die Liste nur, was noch fehlt."))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Euer Tisch ist gedeckt.")
                            .font(Theme.display(32))
                            .tracking(-0.6)
                            .accessibilityAddTraits(.isHeader)
                        Text("Das übernimmt Gnocchi ab jetzt:")
                            .font(.body)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: index < revealed ? "checkmark.circle.fill" : line.symbol)
                                    .font(.title3)
                                    .foregroundStyle(index < revealed ? Theme.success : Theme.inkSecondary)
                                    .frame(width: 28)
                                    .contentTransition(.symbolEffect(.replace))
                                    .accessibilityHidden(true)
                                Text(line.text)
                                    .font(.body.weight(index < revealed ? .medium : .regular))
                                    .foregroundStyle(index < revealed ? Theme.ink : Theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 12)
                            if index < lines.count - 1 { Divider().padding(.leading, 42) }
                        }
                    }
                    .gnCard(padding: 16)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 10) {
                Button("Konto erstellen", action: register).buttonStyle(.ink)
                Button("Ich habe schon ein Konto", action: signIn).buttonStyle(.soft)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 12)
        }
        .task {
            guard !reduceMotion else { revealed = lines.count; return }
            for index in 1...lines.count {
                try? await Task.sleep(for: .milliseconds(480))
                withAnimation(Theme.spring) { revealed = index }
            }
        }
    }
}

#Preview {
    OnboardingFlow { _ in }
        .environment(AppPreferences())
}
