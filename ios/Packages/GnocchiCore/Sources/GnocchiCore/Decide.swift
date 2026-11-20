// Wire format and rule order follow lib/decide.ts.
public enum DecideGame: String, Codable, CaseIterable, Identifiable, Sendable {
    case swipe, duell, rad, loeffel, jagd, zug

    public var id: Self { self }
    public var candidateCount: Int { self == .swipe ? 18 : 12 }
}

public enum DecideValue: Codable, Equatable, Sendable {
    case object([String: Self]), array([Self]), string(String), number(Double), bool(Bool), null

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let object = try? value.decode([String: Self].self) { self = .object(object) }
        else if let array = try? value.decode([Self].self) { self = .array(array) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else { self = .null }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .object(fields): try value.encode(fields)
        case let .array(elements): try value.encode(elements)
        case let .string(text): try value.encode(text)
        case let .number(number): try value.encode(number)
        case let .bool(bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }

    subscript(key: String) -> Self {
        guard case let .object(fields) = self else { return .null }
        return fields[key] ?? .null
    }

    var elements: [Self] {
        if case let .array(elements) = self { return elements }
        return []
    }

    var text: String? {
        if case let .string(text) = self { return text }
        return nil
    }

    func integer(max: Int) -> Int {
        guard case let .number(number) = self, number.isFinite else { return 0 }
        return Int(Swift.max(0, Swift.min(Double(max), number.rounded())))
    }

    public static func counts(_ fields: [String: Int]) -> Self {
        .object(fields.mapValues { .number(Double($0)) })
    }
}

public struct DecideState: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case deck, finale, sieb, duell, lose, loeffel, jagd, zug, fertig
    }

    // Lobby rows are stored as an empty object.
    public var phase: Phase?
    public var deck: [String]?
    public var deckNo: Int?
    public var seen: [String]?
    public var score: [String: Int]?
    public var options: [String]?
    public var pairs: [[String]]?
    public var stage: Int?
    public var reveal: Reveal?

    public struct Reveal: Codable, Equatable, Sendable {
        public let kind: String
        public var fans: Int?
        public var options: [String]?
        public var weights: [Int]?
        public var totals: [Int]?
        public var mins: [Int]?
        public var taps: Int?
    }
}

public struct DecideAdvance: Sendable {
    public let winner: String?
    public let state: DecideState
}

public enum Decide {
    public static let tickets = 3
    public static let spoons = 5
    public static let spoonsPerDish = 3
    public static let huntSeconds = 20
    public static let huntShows = 4
    public static let huntVisibleSeconds = 1.5

    public static func initial(game: DecideGame, candidates: [String]) -> DecideState {
        if game == .swipe {
            return DecideState(phase: .deck, deck: Array(candidates.prefix(6)), deckNo: 0, seen: [], score: [:])
        }
        return DecideState(phase: .sieb, options: Array(candidates.prefix(12)))
    }

    public static func advance(game: DecideGame, state: DecideState, submissions: [DecideValue],
                               candidates: [String], seed: Int, round: Int) -> DecideAdvance? {
        var random = roundRandom(seed: seed, round: round)
        let options = state.options ?? []
        let pairs = state.pairs ?? []
        let score = state.score ?? [:]
        switch state.phase {
        case .deck:
            let deck = state.deck ?? []
            let deckNo = state.deckNo ?? 0
            var updated = score
            for id in deck {
                updated[id, default: 0] += submissions.reduce(0) { $0 + $1[id].integer(max: 2) }
            }
            let common = deck.filter { id in submissions.allSatisfy { $0[id].integer(max: 2) >= 1 } }
            if let winner = best(common, using: &random, value: { [updated[$0, default: 0]] }) {
                return finished(winner, .init(kind: "match", fans: max(1, submissions.count)))
            }
            let seen = (state.seen ?? []) + deck
            let rest = candidates.filter { !seen.contains($0) }
            if deckNo + 1 < 3 && rest.count >= 2 {
                return next(.init(phase: .deck, deck: Array(rest.prefix(6)), deckNo: deckNo + 1, seen: seen, score: updated))
            }
            let order = shuffled(seen, &random).sorted { updated[$0, default: 0] > updated[$1, default: 0] }
            if order.count == 1 { return finished(order[0], .init(kind: "einzig")) }
            guard !order.isEmpty else { return nil }
            return next(.init(phase: .finale, score: updated, options: Array(order.prefix(max(2, submissions.count + 1)))))
        case .finale:
            let strikes = submissions.compactMap { $0["strike"].text }
            return finished(best(options, using: &random) { id in
                [-strikes.count { $0 == id }, score[id, default: 0]]
            }, .init(kind: "finale"))
        case .sieb:
            let outs = submissions.reduce(into: [String: Int]()) { totals, submission in
                for id in Set(submission["out"].elements.compactMap(\.text)) { totals[id, default: 0] += 1 }
            }
            var survivors = options.filter { outs[$0] == nil }
            if survivors.isEmpty {
                survivors = Array(shuffled(options, &random).sorted { outs[$0, default: 0] < outs[$1, default: 0] }.prefix(2))
            }
            guard !survivors.isEmpty else { return nil }
            if survivors.count == 1 { return finished(survivors[0], .init(kind: "einzig")) }
            switch game {
            case .duell, .zug:
                let count = [8, 4, 2].first { $0 <= survivors.count } ?? 2
                let ids = Array(shuffled(survivors, &random).prefix(count))
                return next(.init(phase: game == .zug ? .zug : .duell, pairs: pairUp(ids), stage: 0))
            case .rad:
                return next(.init(phase: .lose, options: Array(survivors.prefix(8))))
            case .jagd:
                return next(.init(phase: .jagd, options: Array(survivors.prefix(6))))
            default:
                return next(.init(phase: .loeffel, options: Array(survivors.prefix(6))))
            }
        case .duell, .zug:
            guard !pairs.isEmpty, pairs.allSatisfy({ $0.count == 2 }) else { return nil }
            let tug = state.phase == .zug
            var total = 0
            let winners = pairs.enumerated().map { index, pair in
                let counts = submissions.reduce(into: [0, 0]) { counts, vote in
                    if tug {
                        let taps = vote["taps"].elements
                        guard taps.indices.contains(index) else { return }
                        let sides = taps[index].elements
                        for side in 0..<min(2, sides.count) {
                            counts[side] += sides[side].integer(max: Tug.seconds * Tug.maxTapsPerSecond)
                        }
                    } else {
                        let picks = vote["picks"].elements.compactMap(\.text)
                        if picks.indices.contains(index), let side = pair.firstIndex(of: picks[index]) { counts[side] += 1 }
                    }
                }
                total += counts[0] + counts[1]
                if counts[0] == counts[1] { return pair[random.next() < 0.5 ? 0 : 1] }
                return pair[counts[0] > counts[1] ? 0 : 1]
            }
            if winners.count == 1 { return finished(winners[0], .init(kind: tug ? "zug" : "duell", taps: tug ? total : nil)) }
            return next(.init(phase: state.phase, pairs: pairUp(winners), stage: (state.stage ?? 0) + 1))
        case .lose:
            guard !options.isEmpty else { return nil }
            let weights = options.map { id in 1 + submissions.reduce(0) { $0 + $1["tickets"][id].integer(max: tickets) } }
            var draw = random.next() * Double(weights.reduce(0, +))
            let index = weights.indices.dropLast().first { index in
                draw -= Double(weights[index])
                return draw <= 0
            } ?? weights.count - 1
            return finished(options[index], .init(kind: "rad", options: options, weights: weights))
        case .loeffel, .jagd:
            let hunt = state.phase == .jagd
            let key = hunt ? "caught" : "spoons"
            let limit = hunt ? huntShows : spoonsPerDish
            let scores = options.map { id in submissions.map { $0[key][id].integer(max: limit) } }
            let totals = scores.map { $0.reduce(0, +) }
            let minima = scores.map { $0.min() ?? 0 }
            let index = best(Array(options.indices), using: &random) { [minima[$0], totals[$0]] }
            return finished(index.map { options[$0] }, .init(kind: hunt ? "jagd" : "loeffel", options: options, totals: totals, mins: minima))
        case .fertig, nil:
            return nil
        }
    }

    private static func best<ID>(_ ids: [ID], using random: inout SeededRandom, value: (ID) -> [Int]) -> ID? {
        shuffled(ids, &random).sorted { value($1).lexicographicallyPrecedes(value($0)) }.first
    }

    private static func pairUp(_ ids: [String]) -> [[String]] {
        stride(from: 0, to: max(0, ids.count - 1), by: 2).map { [ids[$0], ids[$0 + 1]] }
    }

    private static func next(_ state: DecideState) -> DecideAdvance {
        DecideAdvance(winner: nil, state: state)
    }

    private static func finished(_ winner: String?, _ reveal: DecideState.Reveal) -> DecideAdvance? {
        guard let winner else { return nil }
        return DecideAdvance(winner: winner, state: .init(phase: .fertig, reveal: reveal))
    }
}
