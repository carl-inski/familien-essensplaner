import { describe, expect, it } from "vitest";
import { DECK_SIZE, SIEVE_SIZE, advance, initialState, pickCandidates, rng, roundSubmissions, shuffled, zugDuration, zugTimeline, type DecideState, type Game } from "../lib/decide";
import type { CookStats } from "../lib/types";

const ids = (n: number) => Array.from({ length: n }, (_, i) => `r${i + 1}`);
const recipe = (id: string, extra: Partial<{ diet: "fleisch" | "fisch" | "vegetarisch"; tags: string[]; folder_id: string | null }> = {}) => ({
  id,
  diet: extra.diet ?? ("vegetarisch" as const),
  cookbook_id: null,
  tags: extra.tags ?? [],
  categories: [],
  folder_id: extra.folder_id ?? null,
});

/** Spielt eine Runde bis zum Ende: `play` liefert je Person die Abgabe zum aktuellen Zustand */
function playOut(game: Game, candidates: string[], players: number, play: (state: DecideState, player: number) => unknown, seed = 7) {
  let state = initialState(game, candidates);
  for (let round = 0; round < 20; round++) {
    const subs = Array.from({ length: players }, (_, p) => play(state, p));
    const next = advance(game, state, subs, candidates, seed, round);
    if (next.done) return { winner: next.winner, state: next.state, rounds: round + 1 };
    state = next.state;
  }
  throw new Error("Runde endet nicht");
}

describe("Zufall mit Seed", () => {
  it("liefert auf jedem Gerät dieselbe Folge", () => {
    const a = rng(42);
    const b = rng(42);
    expect([a(), a(), a()]).toEqual([b(), b(), b()]);
    expect(shuffled(ids(8), rng(5))).toEqual(shuffled(ids(8), rng(5)));
    expect(shuffled(ids(8), rng(5))).not.toEqual(shuffled(ids(8), rng(6)));
  });
});

describe("Kandidaten", () => {
  const today = "2026-11-11";
  const recipes = ids(30).map((id) => recipe(id));

  it("zieht die gewünschte Zahl ohne Doppelte, mit gleichem Seed gleich", () => {
    const a = pickCandidates(recipes, new Map(), [], today, today, 3, { count: 12 });
    expect(a).toHaveLength(12);
    expect(new Set(a).size).toBe(12);
    expect(pickCandidates(recipes, new Map(), [], today, today, 3, { count: 12 })).toEqual(a);
    expect(pickCandidates(recipes, new Map(), [], today, today, 4, { count: 12 })).not.toEqual(a);
  });

  it("lässt gerade Gekochtes und schon Geplantes weg, solange genug anderes da ist", () => {
    const stats = new Map<string, CookStats>([["r1", { recipe_id: "r1", last_cooked_on: "2026-11-09", times_cooked: 1, days_since: 2 }]]);
    const planned = [{ date: "2026-11-12", recipe_id: "r2", diet: "vegetarisch" as const }];
    const picked = pickCandidates(recipes, stats, planned, today, today, 1, { count: 18 });
    expect(picked).not.toContain("r1");
    expect(picked).not.toContain("r2");
  });

  it("füllt mit gesperrten Rezepten auf, wenn die Sammlung klein ist", () => {
    const small = ids(3).map((id) => recipe(id));
    const stats = new Map<string, CookStats>(small.map((r) => [r.id, { recipe_id: r.id, last_cooked_on: "2026-11-10", times_cooked: 1, days_since: 1 }]));
    expect(pickCandidates(small, stats, [], today, today, 1, { count: 12 }).sort()).toEqual(["r1", "r2", "r3"]);
  });

  it("bleibt im gewählten Ordner und nimmt dort auch Kuchen", () => {
    const mixed = [recipe("a", { folder_id: "f1", tags: ["kuchen"] }), recipe("b", { folder_id: "f1" }), recipe("c"), recipe("d", { tags: ["kuchen"] })];
    expect(pickCandidates(mixed, new Map(), [], today, today, 1, { count: 12, folderId: "f1" }).sort()).toEqual(["a", "b"]);
    expect(pickCandidates(mixed, new Map(), [], today, today, 1, { count: 12 }).sort()).toEqual(["b", "c"]);
  });
});

describe("Swipen", () => {
  const candidates = ids(18);

  it("endet beim ersten Gericht, das alle mögen", () => {
    const { winner, rounds, state } = playOut("swipe", candidates, 3, (s, p) => {
      if (s.phase !== "deck") throw new Error("unerwartet");
      // alle mögen r4; sonst mag jede Person nur ihr eigenes
      return Object.fromEntries(s.deck.map((id) => [id, id === "r4" || id === `r${p + 1}` ? 1 : 0]));
    });
    expect(winner).toBe("r4");
    expect(rounds).toBe(1);
    expect(state).toEqual({ phase: "fertig", reveal: { kind: "match", fans: 3 } });
  });

  it("bevorzugt bei mehreren gemeinsamen Ja das mit „Unbedingt“", () => {
    const { winner } = playOut("swipe", candidates, 2, (s, p) => {
      if (s.phase !== "deck") throw new Error("unerwartet");
      return Object.fromEntries(s.deck.map((id) => [id, id === "r2" ? (p === 0 ? 2 : 1) : id === "r5" ? 1 : 0]));
    });
    expect(winner).toBe("r2");
  });

  it("teilt neue Stapel aus und geht nach drei ohne Match ins Finale", () => {
    let state = initialState("swipe", candidates);
    const nobody = (s: DecideState) => (s.phase === "deck" ? Object.fromEntries(s.deck.map((id) => [id, 0])) : {});
    const decks: string[][] = [];
    for (let round = 0; round < 3; round++) {
      if (state.phase !== "deck") throw new Error("unerwartet");
      decks.push(state.deck);
      const next = advance("swipe", state, [nobody(state), nobody(state)], candidates, 1, round);
      if (next.done) throw new Error("zu früh fertig");
      state = next.state;
    }
    expect(decks.map((d) => d.length)).toEqual([DECK_SIZE, DECK_SIZE, DECK_SIZE]);
    expect(new Set(decks.flat()).size).toBe(18);
    expect(state.phase).toBe("finale");
    // 2 Personen → 3 Gerichte: selbst wenn beide streichen, bleibt eines
    if (state.phase === "finale") expect(state.options).toHaveLength(3);
  });

  it("Finale: es gewinnt nie ein gestrichenes Gericht", () => {
    for (let seed = 0; seed < 40; seed++) {
      const struck = new Set<string>();
      const { winner } = playOut(
        "swipe",
        candidates,
        4,
        (s, p) => {
          if (s.phase === "deck") return Object.fromEntries(s.deck.map((id, i) => [id, (i + p) % 4 === 0 ? 0 : 1])); // nie ein gemeinsames Ja
          if (s.phase === "finale") {
            expect(s.options).toHaveLength(5);
            struck.add(s.options[p]);
            return { strike: s.options[p] };
          }
          throw new Error("unerwartet");
        },
        seed,
      );
      expect(struck.size).toBe(4);
      expect(struck.has(winner)).toBe(false);
    }
  });

  it("allein: ein Ja genügt", () => {
    const { winner } = playOut("swipe", candidates, 1, (s) => (s.phase === "deck" ? { r3: 1 } : {}));
    expect(winner).toBe("r3");
  });
});

describe("Aussieben", () => {
  const candidates = ids(SIEVE_SIZE);

  it.each(["duell", "rad", "loeffel"] as Game[])("%s: was jemand streicht, kann nicht gewinnen", (game) => {
    for (let seed = 0; seed < 40; seed++) {
      const out = [["r1", "r2", "r3"], ["r3", "r4"], ["r12"]];
      const { winner } = playOut(
        game,
        candidates,
        3,
        (s, p) => {
          if (s.phase === "sieb") return { out: out[p] };
          if (s.phase === "duell") return { picks: s.pairs.map((pair) => pair[p % 2]) };
          if (s.phase === "lose") return { tickets: { [s.options[p]]: 3 } };
          if (s.phase === "loeffel") return { spoons: { [s.options[0]]: 3, [s.options[p + 1]]: 2 } };
          throw new Error("unerwartet");
        },
        seed,
      );
      expect(out.flat()).not.toContain(winner);
    }
  });

  it("bleibt genau eines übrig, gewinnt es sofort", () => {
    const { winner, rounds, state } = playOut("duell", candidates, 2, (_, p) => ({ out: p === 0 ? candidates.slice(0, 6) : candidates.slice(6, 11) }));
    expect(winner).toBe("r12");
    expect(rounds).toBe(1);
    expect(state).toEqual({ phase: "fertig", reveal: { kind: "einzig" } });
  });

  it("ist alles gestrichen, treten die am wenigsten abgelehnten an", () => {
    const next = advance("rad", initialState("rad", candidates), [{ out: candidates }, { out: candidates.slice(0, 10) }], candidates, 3, 0);
    expect(next.done).toBe(false);
    if (!next.done && next.state.phase === "lose") expect([...next.state.options].sort()).toEqual(["r11", "r12"]);
  });

  it("ignoriert kaputte Abgaben", () => {
    const next = advance("loeffel", initialState("loeffel", candidates), [null, { out: "r1" }, { out: ["gibt-es-nicht", 5] }], candidates, 3, 0);
    expect(next.done).toBe(false);
    if (!next.done && next.state.phase === "loeffel") expect(next.state.options).toEqual(candidates.slice(0, 6));
  });
});

describe("Duell", () => {
  it("spielt 8 → 4 → 2 → 1, die Mehrheit kommt weiter", () => {
    const candidates = ids(SIEVE_SIZE);
    const stages: number[] = [];
    const { winner } = playOut("duell", candidates, 3, (s) => {
      if (s.phase === "sieb") return { out: [] };
      if (s.phase !== "duell") throw new Error("unerwartet");
      stages.push(s.pairs.length);
      // alle wählen immer das Gericht mit der kleineren Nummer
      return { picks: s.pairs.map(([a, b]) => (Number(a.slice(1)) < Number(b.slice(1)) ? a : b)) };
    });
    expect(stages.filter((_, i) => i % 3 === 0)).toEqual([4, 2, 1]);
    expect(Number(winner.slice(1))).toBeLessThanOrEqual(5); // der kleinste der 8 Gelosten
  });

  it("Gleichstand entscheidet der Seed – auf allen Geräten gleich", () => {
    const state: DecideState = { phase: "duell", pairs: [["a", "b"]], stage: 2 };
    const subs = [{ picks: ["a"] }, { picks: ["b"] }];
    const one = advance("duell", state, subs, ["a", "b"], 99, 3);
    expect(advance("duell", state, subs, ["a", "b"], 99, 3)).toEqual(one);
    const winners = new Set(Array.from({ length: 30 }, (_, seed) => {
      const r = advance("duell", state, subs, ["a", "b"], seed, 3);
      return r.done ? r.winner : "";
    }));
    expect(winners).toEqual(new Set(["a", "b"]));
  });
});

describe("Glücksrad", () => {
  it("mehr Lose, größeres Feld; jedes Feld bleibt möglich", () => {
    const state: DecideState = { phase: "lose", options: ["a", "b", "c"] };
    const subs = [{ tickets: { a: 3 } }, { tickets: { a: 2, b: 1 } }];
    const wins = { a: 0, b: 0, c: 0 };
    for (let seed = 0; seed < 600; seed++) {
      const r = advance("rad", state, subs, ["a", "b", "c"], seed, 1);
      if (!r.done || r.state.phase !== "fertig" || r.state.reveal.kind !== "rad") throw new Error("unerwartet");
      expect(r.state.reveal.weights).toEqual([6, 2, 1]);
      wins[r.winner as "a" | "b" | "c"]++;
    }
    expect(wins.a).toBeGreaterThan(wins.b);
    expect(wins.b).toBeGreaterThan(wins.c);
    expect(wins.c).toBeGreaterThan(0);
  });

  it("begrenzt geschummelte Lose", () => {
    const r = advance("rad", { phase: "lose", options: ["a", "b"] }, [{ tickets: { a: 999 } }], ["a", "b"], 1, 1);
    if (!r.done || r.state.phase !== "fertig" || r.state.reveal.kind !== "rad") throw new Error("unerwartet");
    expect(r.state.reveal.weights).toEqual([4, 1]);
  });
});

describe("Löffel", () => {
  it("es gewinnt, was allen schmeckt – nicht der Liebling eines Einzelnen", () => {
    const state: DecideState = { phase: "loeffel", options: ["a", "b", "c"] };
    // a: 3+3+0 = 6 Löffel, aber eine Person gibt nichts. b: 2+2+2 = 6, von allen.
    const subs = [{ spoons: { a: 3, b: 2 } }, { spoons: { a: 3, b: 2 } }, { spoons: { b: 2, c: 3 } }];
    const r = advance("loeffel", state, subs, ["a", "b", "c"], 1, 1);
    expect(r.done && r.winner).toBe("b");
    if (r.done && r.state.phase === "fertig" && r.state.reveal.kind === "loeffel") {
      expect(r.state.reveal.totals).toEqual([6, 6, 3]);
      expect(r.state.reveal.mins).toEqual([0, 2, 0]);
    }
  });
});

describe("Rundenabgaben", () => {
  it("wartet, bis alle die aktuelle Runde abgegeben haben", () => {
    const a = { round_done: 1, data: { "0": "a0", "1": "a1" } };
    const b = { round_done: 0, data: { "0": "b0" } };
    expect(roundSubmissions([a, b], 0)).toEqual(["a0", "b0"]);
    expect(roundSubmissions([a, b], 1)).toBeNull();
    expect(roundSubmissions([], 0)).toBeNull();
  });
});

describe("Tellerjagd", () => {
  it("nach dem Aussieben fliegen höchstens sechs Gerichte", () => {
    const next = advance("jagd", initialState("jagd", ids(SIEVE_SIZE)), [{ out: [] }], ids(SIEVE_SIZE), 1, 0);
    expect(next.done).toBe(false);
    if (!next.done) expect(next.state).toMatchObject({ phase: "jagd" });
    if (!next.done && next.state.phase === "jagd") expect(next.state.options).toHaveLength(6);
  });

  it("es gewinnt, was alle geschnappt haben, nicht der Rekord eines Einzelnen", () => {
    const state: DecideState = { phase: "jagd", options: ["a", "b", "c"] };
    const subs = [{ caught: { a: 4, b: 1 } }, { caught: { a: 4, b: 1 } }, { caught: { b: 1, c: 4 } }];
    const r = advance("jagd", state, subs, ["a", "b", "c"], 1, 1);
    expect(r.done && r.winner).toBe("b");
    if (r.done && r.state.phase === "fertig" && r.state.reveal.kind === "jagd") {
      expect(r.state.reveal.totals).toEqual([8, 3, 4]);
      expect(r.state.reveal.mins).toEqual([0, 1, 0]);
    }
  });

  it("mehr Fänge als Auftritte zählen nicht", () => {
    const r = advance("jagd", { phase: "jagd", options: ["a", "b"] }, [{ caught: { a: 99, b: 2 } }], ["a", "b"], 1, 1);
    if (r.done && r.state.phase === "fertig" && r.state.reveal.kind === "jagd") expect(r.state.reveal.totals).toEqual([4, 2]);
  });

  it("was jemand gestrichen hat, fliegt gar nicht erst vorbei", () => {
    const next = advance("jagd", initialState("jagd", ids(SIEVE_SIZE)), [{ out: ["r1", "r2"] }, { out: ["r3"] }], ids(SIEVE_SIZE), 1, 0);
    if (!next.done && next.state.phase === "jagd") expect(next.state.options).not.toEqual(expect.arrayContaining(["r1"]));
    if (!next.done && next.state.phase === "jagd") for (const id of ["r1", "r2", "r3"]) expect(next.state.options).not.toContain(id);
  });
});

describe("Tauziehen", () => {
  it("spielt ein Turnier; die meisten Taps der ganzen Familie ziehen weiter", () => {
    const candidates = ids(SIEVE_SIZE);
    const stages: number[] = [];
    const { winner, state } = playOut("zug", candidates, 2, (s, p) => {
      if (s.phase === "sieb") return { out: [] };
      if (s.phase !== "zug") throw new Error("unerwartet");
      if (p === 0) stages.push(s.pairs.length);
      // Person 0 tippt wie wild für die kleinere Nummer, Person 1 etwas weniger für die größere
      return { taps: s.pairs.map(([a, b]) => {
        const small = Number(a.slice(1)) < Number(b.slice(1)) ? 0 : 1;
        const t: [number, number] = [0, 0];
        if (p === 0) t[small] = 40;
        else t[1 - small] = 30;
        return t;
      }) };
    });
    expect(stages).toEqual([4, 2, 1]);
    expect(Number(winner.slice(1))).toBeLessThanOrEqual(5);
    expect(state).toMatchObject({ phase: "fertig", reveal: { kind: "zug" } });
  });

  it("begrenzt unmögliche Tap-Zahlen", () => {
    const state: DecideState = { phase: "zug", pairs: [["a", "b"]], stage: 2 };
    // 5 s × 14 Taps = höchstens 70; 10.000 für a zählen wie 70, b gewinnt mit 2 × 60
    const r = advance("zug", state, [{ taps: [[10000, 60]] }, { taps: [[0, 60]] }], ["a", "b"], 1, 3);
    expect(r.done && r.winner).toBe("b");
  });

  it("niemand tippt: der Zufall der Runde entscheidet, auf allen Geräten gleich", () => {
    const state: DecideState = { phase: "zug", pairs: [["a", "b"]], stage: 0 };
    const one = advance("zug", state, [{ taps: [] }], ["a", "b"], 42, 1);
    expect(advance("zug", state, [{ taps: [] }], ["a", "b"], 42, 1)).toEqual(one);
  });
});

describe("Tauziehen: gemeinsamer Takt", () => {
  // Vorlauf 1,5 s, je Duell 3 s Countdown, 5 s ziehen, 1,5 s Pause
  it("alle Handys sind zur selben Serverzeit im selben Abschnitt", () => {
    expect(zugTimeline(0, 2)).toEqual({ done: false, duel: 0, phase: "wait", msLeft: 1500 });
    expect(zugTimeline(1500, 2)).toEqual({ done: false, duel: 0, phase: "count", msLeft: 3000 });
    expect(zugTimeline(4500, 2)).toEqual({ done: false, duel: 0, phase: "pull", msLeft: 5000 });
    expect(zugTimeline(9400, 2)).toEqual({ done: false, duel: 0, phase: "pull", msLeft: 100 });
    expect(zugTimeline(9500, 2)).toEqual({ done: false, duel: 0, phase: "pause", msLeft: 1500 });
    expect(zugTimeline(11000, 2)).toEqual({ done: false, duel: 1, phase: "count", msLeft: 3000 });
    expect(zugTimeline(14000, 2)).toEqual({ done: false, duel: 1, phase: "pull", msLeft: 5000 });
  });

  it("nach dem letzten Duell ist Schluss – auch wer zu spät kommt, gibt sofort ab", () => {
    expect(zugTimeline(1500 + 2 * 9500, 2)).toMatchObject({ done: true });
    expect(zugTimeline(999999, 1)).toMatchObject({ done: true });
  });

  it("vor dem Start (Uhr leicht vor) wird gewartet", () => {
    expect(zugTimeline(-800, 3)).toEqual({ done: false, duel: 0, phase: "wait", msLeft: 2300 });
  });

  it("Gesamtdauer passt zur Zahl der Duelle", () => {
    expect(zugDuration(4)).toBe(1500 + 4 * 9500);
  });
});
