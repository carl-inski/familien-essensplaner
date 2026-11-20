import { describe, expect, it } from "vitest";
import { isDinnerCandidate, isMealCandidate, pickSuggestion, suggestionCandidates } from "../lib/suggest";
import type { CookStats, Diet } from "../lib/types";
import { cookStatsFromHistory } from "../lib/history";
import { slotKey } from "../lib/meals";

const today = "2026-10-23";
const r = (id: string, diet: Diet, cookbook_id: string | null = null) => ({ id, diet, cookbook_id });

it("schlägt ein Fleischgericht auch nach einer Fleischmahlzeit am selben Tag vor", () => {
  const planned = [{ date: slotKey("2026-10-26", "mittag"), diet: "fleisch" as const, recipe_id: "geplant" }];
  const recipes = [r("geplant", "fleisch"), r("neu", "fleisch")];
  expect(pickSuggestion(recipes, new Map(), planned, today, () => 0)?.id).toBe("neu");
});

describe("14-Tage-Sperre und Gewichtung", () => {
  const stats = new Map<string, CookStats>([
    ["recent", { recipe_id: "recent", last_cooked_on: "2026-10-15", times_cooked: 3, days_since: 8 }],
    ["old", { recipe_id: "old", last_cooked_on: "2026-06-01", times_cooked: 1, days_since: 144 }],
    ["edge", { recipe_id: "edge", last_cooked_on: "2026-10-09", times_cooked: 1, days_since: 14 }],
  ]);

  it("schlägt in den letzten 14 Tagen Gekochtes nie vor", () => {
    const recipes = [r("recent", "vegetarisch"), r("old", "vegetarisch"), r("never", "vegetarisch"), r("edge", "vegetarisch")];
    const ids = suggestionCandidates(recipes, stats, [], today).map((c) => c.id);
    expect(ids).not.toContain("recent");
    expect(ids).toEqual(["old", "never", "edge"]);
    for (let i = 0; i < 100; i++) expect(pickSuggestion(recipes, stats, [], today)?.id).not.toBe("recent");
  });

  it("schlägt nichts doppelt in derselben Woche vor", () => {
    const ids = suggestionCandidates([r("a", "vegetarisch"), r("b", "fisch")], new Map(), [{ date: "2026-10-26", recipe_id: "a" }], today).map((c) => c.id);
    expect(ids).toEqual(["b"]);
  });
});

describe("Kochhistorie", () => {
  it("gekocht ✓ erhöht times_cooked, Rückgängig stellt den alten Stand her", () => {
    const history = [{ recipe_id: "a", cooked_on: "2026-09-01" }];
    const before = cookStatsFromHistory(history, today).get("a")!;
    expect(before).toMatchObject({ times_cooked: 1, last_cooked_on: "2026-09-01" });

    const cooked = [...history, { recipe_id: "a", cooked_on: "2026-10-22" }];
    const after = cookStatsFromHistory(cooked, today).get("a")!;
    expect(after).toMatchObject({ times_cooked: 2, last_cooked_on: "2026-10-22", days_since: 1 });

    const undone = cooked.slice(0, 1);
    expect(cookStatsFromHistory(undone, today).get("a")).toEqual(before);
  });
});

describe("Abendessen-Kandidaten", () => {
  it("schließt Snacks und Süßes aus", () => {
    expect(isDinnerCandidate({ tags: ["snack", "fitness"], categories: ["Snack", "Fitness"] })).toBe(false);
    expect(isDinnerCandidate({ tags: ["pasta", "fisch"], categories: ["Pasta", "Fisch"] })).toBe(true);
  });
});

it("schlägt für Frühstück und Snacks passend markierte Rezepte vor", () => {
  const breakfast = { tags: ["Frühstück"], categories: [] };
  const snack = { tags: [], categories: ["Snack"] };
  const dinner = { tags: [], categories: ["Pasta"] };
  expect([breakfast, snack, dinner].filter((recipe) => isMealCandidate(recipe, "fruehstueck"))).toEqual([breakfast]);
  expect([breakfast, snack, dinner].filter((recipe) => isMealCandidate(recipe, "snack"))).toEqual([snack]);
});

describe("Mittag und Abend", () => {
  it("ordnet Slots als Mo mittag < Mo abend < Di mittag", async () => {
    const { slotKey } = await import("../lib/meals");
    expect(slotKey("2026-10-26", "mittag") < slotKey("2026-10-26", "abend")).toBe(true);
    expect(slotKey("2026-10-26", "abend") < slotKey("2026-10-27", "mittag")).toBe(true);
  });
});
