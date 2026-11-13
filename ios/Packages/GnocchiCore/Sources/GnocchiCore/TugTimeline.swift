// Tauziehen: gemeinsamer Takt aller Geräte – wie zugTimeline() in lib/decide.ts.
// Gemessen ab der Serverzeit, zu der die Duelle ausgelost wurden.

public enum Tug {
    public static let seconds = 5
    public static let maxTapsPerSecond = 14
    public static let leadMs = 1500
    public static let countMs = 3000
    public static let pauseMs = 1500
    static var duelMs: Int { countMs + seconds * 1000 + pauseMs }

    public enum Phase: String, Sendable { case wait, count, pull, pause }

    public enum Step: Equatable, Sendable {
        case done
        case running(duel: Int, phase: Phase, msLeft: Int)
    }

    /// Wo im gemeinsamen Ablauf steht man, `elapsedMs` nach dem Auslosen?
    public static func timeline(elapsedMs: Int, duels: Int) -> Step {
        if elapsedMs < leadMs { return .running(duel: 0, phase: .wait, msLeft: leadMs - elapsedMs) }
        let t = elapsedMs - leadMs
        let duel = t / duelMs
        if duel >= duels { return .done }
        let within = t - duel * duelMs
        if within < countMs { return .running(duel: duel, phase: .count, msLeft: countMs - within) }
        if within < countMs + seconds * 1000 { return .running(duel: duel, phase: .pull, msLeft: countMs + seconds * 1000 - within) }
        return .running(duel: duel, phase: .pause, msLeft: duelMs - within)
    }

    public static func duration(duels: Int) -> Int { leadMs + duels * duelMs }
}
