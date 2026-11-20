// Zufall mit Seed – bitgenau wie rng() in lib/decide.ts (mulberry32).
// Web und iPhone müssen aus demselben Seed dieselbe Folge ziehen, sonst bekämen
// Familien mit gemischten Geräten in derselben Runde verschiedene Sieger.

public struct SeededRandom: Sendable {
    private var state: UInt32

    public init(seed: Int) {
        // JS: seed >>> 0
        state = UInt32(truncatingIfNeeded: seed)
    }

    /// Nächste Zahl in [0, 1)
    public mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

/// Fisher-Yates wie shuffled() in lib/decide.ts
public func shuffled<T>(_ list: [T], _ random: inout SeededRandom) -> [T] {
    var a = list
    var i = a.count - 1
    while i > 0 {
        let j = Int(random.next() * Double(i + 1))
        a.swapAt(i, j)
        i -= 1
    }
    return a
}

/// Zufall einer bestimmten Runde, wie roundRand() in lib/decide.ts
public func roundRandom(seed: Int, round: Int) -> SeededRandom {
    SeededRandom(seed: seed + (round + 1) * 7919)
}
