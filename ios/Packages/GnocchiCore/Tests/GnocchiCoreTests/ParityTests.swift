// Gleichlauf mit der Web-App: Die Erwartungswerte stammen direkt aus lib/decide.ts
// (erzeugt mit tsx). Ändert sich dort etwas, müssen diese Werte neu erzeugt werden.

import Testing
@testable import GnocchiCore

@Suite("Gleich wie die Web-App")
struct ParityTests {
    @Test("Zufall mit Seed 42 liefert dieselbe Folge wie rng(42)")
    func seed42() {
        var r = SeededRandom(seed: 42)
        let expected = [0.6011037519201636, 0.44829055899754167, 0.8524657934904099, 0.6697340414393693, 0.17481389874592423]
        for e in expected { #expect(r.next() == e) }
    }

    @Test("auch nahe am größten Seed")
    func seedMax() {
        var r = SeededRandom(seed: 2_147_483_646)
        for e in [0.9936443585902452, 0.3810898973606527, 0.3795308177359402] { #expect(r.next() == e) }
    }

    @Test("Mischen wie shuffled(…, rng(7))")
    func shuffle() {
        var r = SeededRandom(seed: 7)
        #expect(shuffled(["a", "b", "c", "d", "e", "f", "g", "h"], &r) == ["e", "g", "b", "c", "d", "f", "h", "a"])
    }

    @Test("Tauziehen-Takt wie zugTimeline()")
    func tugTimeline() {
        #expect(Tug.timeline(elapsedMs: 0, duels: 2) == .running(duel: 0, phase: .wait, msLeft: 1500))
        #expect(Tug.timeline(elapsedMs: 1500, duels: 2) == .running(duel: 0, phase: .count, msLeft: 3000))
        #expect(Tug.timeline(elapsedMs: 4500, duels: 2) == .running(duel: 0, phase: .pull, msLeft: 5000))
        #expect(Tug.timeline(elapsedMs: 9500, duels: 2) == .running(duel: 0, phase: .pause, msLeft: 1500))
        #expect(Tug.timeline(elapsedMs: 11000, duels: 2) == .running(duel: 1, phase: .count, msLeft: 3000))
        #expect(Tug.timeline(elapsedMs: 20500, duels: 2) == .done)
        #expect(Tug.duration(duels: 4) == 1500 + 4 * 9500)
    }
}
