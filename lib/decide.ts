// Entscheiden: Spielregeln als reine Funktionen (Tests in tests/decide.test.ts).
//
// Vier Spiele, ein Protokoll: Eine Runde hat einen Zustand (`DecideState`), jede
// mitspielende Person gibt genau eine Abgabe ab. Sind alle Abgaben da, rechnet
// `advance` den nächsten Zustand oder den Sieger aus – auf jedem Gerät gleich,
// weil aller Zufall aus dem Seed der Runde kommt.
//
// „Ein Gericht, auf das alle Lust haben“ heißt hier: Es gewinnt nie ein Gericht,
// das jemand abgelehnt hat.
//  - Swipen: Es gewinnt nur, was alle mit „Ja“ gewischt haben. Gibt es nach drei
//    Stapeln kein gemeinsames Ja, kommt das Finale: n + 1 Gerichte, jede Person
//    streicht höchstens eins – mindestens eines bleibt übrig.
//  - Duell, Glücksrad, Löffel: Zuerst wird ausgesiebt. Weiter kommt nur, was
//    niemand gestrichen hat.

import { isDinnerCandidate, suggestionCandidates, weight, type PlannedDish } from "./suggest";
import type { CookStats, Diet, Meal } from "./types";

export type Game = "swipe" | "duell" | "rad" | "loeffel";

export const GAMES: { id: Game; emoji: string; title: string; text: string }[] = [
  { id: "swipe", emoji: "💘", title: "Swipen", text: "Wischt durch die Karten. Das erste Gericht, das alle mögen, gewinnt." },
  { id: "duell", emoji: "⚔️", title: "Duell", text: "Immer zwei Gerichte gegeneinander – bis ein Sieger übrig ist." },
  { id: "rad", emoji: "🎡", title: "Glücksrad", text: "Verteilt eure Lose, dann entscheidet das Rad." },
  { id: "loeffel", emoji: "🥄", title: "Löffel", text: "Fünf Löffel für eure Favoriten. Es gewinnt, was allen schmeckt." },
];

export const DECK_SIZE = 6;
export const MAX_DECKS = 3;
export const SIEVE_SIZE = 12;
export const WHEEL_MAX = 8;
export const SPOON_OPTIONS = 6;
export const TICKETS = 3;
export const SPOONS = 5;
export const SPOONS_PER_DISH = 3;

export type Score = Record<string, number>;

export type DecideState =
  | { phase: "deck"; deck: string[]; deckNo: number; seen: string[]; score: Score }
  | { phase: "finale"; options: string[]; score: Score }
  | { phase: "sieb"; options: string[] }
  | { phase: "duell"; pairs: [string, string][]; stage: number }
  | { phase: "lose"; options: string[] }
  | { phase: "loeffel"; options: string[] }
  | { phase: "fertig"; reveal: Reveal };

export type Reveal =
  | { kind: "match"; fans: number }
  | { kind: "finale" }
  | { kind: "einzig" }
  | { kind: "duell" }
  | { kind: "rad"; options: string[]; weights: number[] }
  | { kind: "loeffel"; options: string[]; totals: number[]; mins: number[] };

export interface DecideSession {
  id: string;
  household_id: string;
  created_by: string | null;
  created_at: string;
  date: string;
  meal: Meal;
  game: Game;
  status: "lobby" | "playing" | "done" | "cancelled";
  round: number;
  seed: number;
  candidates: string[];
  state: DecideState | Record<string, never>;
  winner_recipe_id: string | null;
}

export interface DecidePlayer {
  session_id: string;
  member_id: string;
  joined_at: string;
  round_done: number;
  data: Record<string, unknown>;
}

export type Advance = { done: false; state: DecideState } | { done: true; winner: string; state: DecideState };

// ---------------------------------------------------------------------------
// Zufall mit Seed
// ---------------------------------------------------------------------------

/** mulberry32 – klein, schnell, auf jedem Gerät dieselbe Folge */
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function shuffled<T>(list: T[], rand: () => number): T[] {
  const a = [...list];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const roundRand = (seed: number, round: number) => rng(seed + (round + 1) * 7919);

// ---------------------------------------------------------------------------
// Kandidaten
// ---------------------------------------------------------------------------

export interface CandidateRecipe {
  id: string;
  diet: Diet | null;
  cookbook_id: string | null;
  tags: string[];
  categories: string[];
  folder_id?: string | null;
}

/**
 * Wählt die Gerichte für eine Runde: bevorzugt, was die Vorschlagsregeln erlauben
 * (nicht gerade erst gekocht, nicht schon geplant, Fleischregel) und lange nicht
 * auf dem Tisch war – aber mit Zufall, damit jede Runde anders aussieht. Reicht das
 * nicht, wird mit den übrigen Rezepten aufgefüllt.
 */
export function pickCandidates(
  recipes: CandidateRecipe[],
  stats: Map<string, CookStats>,
  planned: PlannedDish[],
  date: string,
  today: string,
  seed: number,
  opts: { count: number; folderId?: string | null; tag?: string | null },
): string[] {
  const rand = rng(seed);
  let pool = recipes;
  if (opts.folderId) pool = pool.filter((r) => r.folder_id === opts.folderId);
  if (opts.tag) pool = pool.filter((r) => r.tags.includes(opts.tag!));
  // Ohne Ordner/Tag: Kuchen und Snacks sind kein Essen für den Plan
  const meals = opts.folderId || opts.tag ? pool : pool.filter(isDinnerCandidate);
  const allowed = suggestionCandidates(meals, stats, planned, date, today) as CandidateRecipe[];

  const picked: string[] = [];
  const bag = allowed.map((r) => ({ id: r.id, w: weight(r, stats.get(r.id), today) }));
  while (picked.length < opts.count && bag.length) {
    const total = bag.reduce((s, b) => s + b.w, 0);
    let x = rand() * total;
    let i = 0;
    for (; i < bag.length - 1; i++) {
      x -= bag[i].w;
      if (x <= 0) break;
    }
    picked.push(bag[i].id);
    bag.splice(i, 1);
  }
  if (picked.length < opts.count) {
    const rest = shuffled(meals.filter((r) => !picked.includes(r.id)), rand);
    for (const r of rest) {
      if (picked.length >= opts.count) break;
      picked.push(r.id);
    }
  }
  return picked;
}

export const candidateCount = (game: Game) => (game === "swipe" ? DECK_SIZE * MAX_DECKS : SIEVE_SIZE);

// ---------------------------------------------------------------------------
// Rundenablauf
// ---------------------------------------------------------------------------

export function initialState(game: Game, candidates: string[]): DecideState {
  if (game === "swipe") return { phase: "deck", deck: candidates.slice(0, DECK_SIZE), deckNo: 0, seen: [], score: {} };
  return { phase: "sieb", options: candidates.slice(0, SIEVE_SIZE) };
}

const asRecord = (v: unknown): Record<string, unknown> => (v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
const asList = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
const asInt = (v: unknown, max: number) => (typeof v === "number" && Number.isFinite(v) ? Math.max(0, Math.min(max, Math.round(v))) : 0);

/** Bester nach `value` (größer gewinnt); Gleichstand entscheidet der Zufall der Runde */
function best(ids: string[], value: (id: string) => number[], rand: () => number): string {
  const order = shuffled(ids, rand);
  return order.sort((a, b) => {
    const va = value(a);
    const vb = value(b);
    for (let i = 0; i < va.length; i++) if (va[i] !== vb[i]) return vb[i] - va[i];
    return 0;
  })[0];
}

/**
 * Alle Abgaben der Runde sind da → nächster Zustand oder Sieger.
 * `submissions`: je mitspielender Person die Abgabe der aktuellen Runde.
 */
export function advance(game: Game, state: DecideState, submissions: unknown[], candidates: string[], seed: number, round: number): Advance {
  const rand = roundRand(seed, round);
  const n = Math.max(1, submissions.length);

  switch (state.phase) {
    case "deck": {
      const votes = submissions.map(asRecord);
      const score: Score = { ...state.score };
      for (const id of state.deck) score[id] = (score[id] ?? 0) + votes.reduce((s, v) => s + asInt(v[id], 2), 0);
      const common = state.deck.filter((id) => votes.every((v) => asInt(v[id], 2) >= 1));
      if (common.length) {
        const winner = best(common, (id) => [score[id]], rand);
        return { done: true, winner, state: { phase: "fertig", reveal: { kind: "match", fans: n } } };
      }
      const seen = [...state.seen, ...state.deck];
      const rest = candidates.filter((id) => !seen.includes(id));
      if (state.deckNo + 1 < MAX_DECKS && rest.length >= 2) {
        return { done: false, state: { phase: "deck", deck: rest.slice(0, DECK_SIZE), deckNo: state.deckNo + 1, seen, score } };
      }
      // Finale: n + 1 Gerichte, jede Person streicht höchstens eins → eines bleibt sicher
      const order = shuffled(seen, rand).sort((a, b) => (score[b] ?? 0) - (score[a] ?? 0));
      const options = order.slice(0, Math.max(2, n + 1));
      if (options.length === 1) return { done: true, winner: options[0], state: { phase: "fertig", reveal: { kind: "einzig" } } };
      return { done: false, state: { phase: "finale", options, score } };
    }

    case "finale": {
      const strikes = new Map<string, number>();
      for (const s of submissions) {
        const id = asRecord(s).strike;
        if (typeof id === "string" && state.options.includes(id)) strikes.set(id, (strikes.get(id) ?? 0) + 1);
      }
      const winner = best(state.options, (id) => [-(strikes.get(id) ?? 0), state.score[id] ?? 0], rand);
      return { done: true, winner, state: { phase: "fertig", reveal: { kind: "finale" } } };
    }

    case "sieb": {
      const outs = new Map<string, number>();
      for (const s of submissions) for (const id of new Set(asList(asRecord(s).out))) if (state.options.includes(id)) outs.set(id, (outs.get(id) ?? 0) + 1);
      let survivors = state.options.filter((id) => !outs.has(id));
      if (survivors.length === 1) return { done: true, winner: survivors[0], state: { phase: "fertig", reveal: { kind: "einzig" } } };
      if (survivors.length === 0) {
        // Alles gestrichen: die zwei am wenigsten abgelehnten treten an
        survivors = shuffled(state.options, rand).sort((a, b) => (outs.get(a) ?? 0) - (outs.get(b) ?? 0)).slice(0, 2);
        if (survivors.length === 1) return { done: true, winner: survivors[0], state: { phase: "fertig", reveal: { kind: "einzig" } } };
      }
      if (game === "duell") {
        let size = 1;
        while (size * 2 <= Math.min(8, survivors.length)) size *= 2;
        return { done: false, state: { phase: "duell", pairs: pairUp(shuffled(survivors, rand).slice(0, size)), stage: 0 } };
      }
      if (game === "rad") return { done: false, state: { phase: "lose", options: survivors.slice(0, WHEEL_MAX) } };
      return { done: false, state: { phase: "loeffel", options: survivors.slice(0, SPOON_OPTIONS) } };
    }

    case "duell": {
      const picks = submissions.map((s) => asList(asRecord(s).picks));
      const winners = state.pairs.map(([a, b], i) => {
        const forA = picks.filter((p) => p[i] === a).length;
        const forB = picks.filter((p) => p[i] === b).length;
        if (forA !== forB) return forA > forB ? a : b;
        return rand() < 0.5 ? a : b;
      });
      if (winners.length === 1) return { done: true, winner: winners[0], state: { phase: "fertig", reveal: { kind: "duell" } } };
      return { done: false, state: { phase: "duell", pairs: pairUp(winners), stage: state.stage + 1 } };
    }

    case "lose": {
      const weights = state.options.map((id) => 1 + submissions.reduce<number>((s, sub) => s + asInt(asRecord(asRecord(sub).tickets)[id], TICKETS), 0));
      const total = weights.reduce((a, b) => a + b, 0);
      let x = rand() * total;
      let i = 0;
      for (; i < weights.length - 1; i++) {
        x -= weights[i];
        if (x <= 0) break;
      }
      return { done: true, winner: state.options[i], state: { phase: "fertig", reveal: { kind: "rad", options: state.options, weights } } };
    }

    case "loeffel": {
      const per = submissions.map((s) => asRecord(asRecord(s).spoons));
      const totals = state.options.map((id) => per.reduce<number>((s, p) => s + asInt(p[id], SPOONS_PER_DISH), 0));
      const mins = state.options.map((id) => (per.length ? Math.min(...per.map((p) => asInt(p[id], SPOONS_PER_DISH))) : 0));
      const winner = best(state.options, (id) => [mins[state.options.indexOf(id)], totals[state.options.indexOf(id)]], rand);
      return { done: true, winner, state: { phase: "fertig", reveal: { kind: "loeffel", options: state.options, totals, mins } } };
    }

    case "fertig":
      throw new Error("Die Runde ist schon entschieden");
  }
}

function pairUp(ids: string[]): [string, string][] {
  const pairs: [string, string][] = [];
  for (let i = 0; i + 1 < ids.length; i += 2) pairs.push([ids[i], ids[i + 1]]);
  return pairs;
}

/** Abgaben der aktuellen Runde – oder null, solange noch jemand fehlt */
export function roundSubmissions(players: Pick<DecidePlayer, "round_done" | "data">[], round: number): unknown[] | null {
  if (!players.length || players.some((p) => p.round_done < round)) return null;
  return players.map((p) => p.data?.[String(round)]);
}

export const STAGE_LABEL = (pairs: number) => (pairs >= 4 ? "Viertelfinale" : pairs === 2 ? "Halbfinale" : "Finale");

/** Kurzer Auftrag je Phase – steht über dem Spiel */
export function phaseTitle(state: DecideState, players: number): { title: string; text: string } {
  switch (state.phase) {
    case "deck":
      return { title: `Stapel ${state.deckNo + 1}`, text: players > 1 ? "Rechts: Lust drauf. Links: heute nicht. Hoch: unbedingt!" : "Rechts: Lust drauf. Links: heute nicht. Hoch: genau das!" };
    case "finale":
      return { title: "Finale", text: players > 1 ? "Kein gemeinsames Ja. Streich eins, das du gar nicht willst – der Rest spielt um den Sieg." : "Streich eins – das andere gewinnt." };
    case "sieb":
      return { title: "Aussieben", text: "Tippe weg, worauf du heute keine Lust hast." };
    case "duell":
      return { title: STAGE_LABEL(state.pairs.length), text: "Welches soll weiterkommen?" };
    case "lose":
      return { title: "Lose verteilen", text: `Du hast ${TICKETS} Lose. Mehr Lose, mehr Platz auf dem Rad.` };
    case "loeffel":
      return { title: "Löffel verteilen", text: `${SPOONS} Löffel, höchstens ${SPOONS_PER_DISH} pro Gericht. Es gewinnt, was allen schmeckt.` };
    case "fertig":
      return { title: "Entschieden", text: "" };
  }
}
