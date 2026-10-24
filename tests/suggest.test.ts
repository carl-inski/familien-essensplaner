import { describe, expect, it } from "vitest";
import { addingViolatesMeatRule, isDinnerCandidate, meatRuleHint, pickSuggestion, suggestionCandidates, violatesMeatRule } from "../lib/suggest";
import type { CookStats, Diet } from "../lib/types";
import { cookStatsFromHistory } from "../lib/history";

const today = "2026-10-23";
const r = (id: string, diet: Diet, cookbook_id: string | null = null) => ({ id, diet, cookbook_id });

describe("Fleischregel", () => {
  it("erkennt mehr als 1 Fleischgericht in 3 Gerichten", () => {
    expect(violatesMeatRule([
      { date: "2026-10-26", diet: "fleisch" },
      { date: "2026-10-27", diet: "vegetarisch" },
      { date: "2026-10-28", diet: "fleisch" },
    ])).toBe(true);
    expect(violatesMeatRule([
      { date: "2026-10-26", diet: "fleisch" },
      { date: "2026-10-27", diet: "fisch" },
      { date: "2026-10-28", diet: "vegetarisch" },
      { date: "2026-10-29", diet: "fleisch" },
    ])).toBe(false);
  });

  it("Vorschläge verletzen die Regel nie", () => {
    const recipes = [r("m1", "fleisch"), r("m2", "fleisch"), r("v1", "vegetarisch"), r("f1", "fisch")];
    const planned = [{ date: "2026-10-26", diet: "fleisch" as Diet, recipe_id: "x" }];
    // Dienstag liegt im selben 3er-Fenster wie Montag → kein Fleisch
    const ids = suggestionCandidates(recipes, new Map(), planned, "2026-10-27", today).map((c) => c.id);
    expect(ids).toEqual(["v1", "f1"]);
    for (let i = 0; i < 50; i++) {
      const pick = pickSuggestion(recipes, new Map(), planned, "2026-10-27", today)!;
      expect(addingViolatesMeatRule(planned, { date: "2026-10-27", diet: pick.diet })).toBe(false);
    }
  });

  it("gibt beim manuellen Einplanen nur einen Hinweis", () => {
    const planned = [{ date: "2026-10-26", diet: "fleisch" as Diet, recipe_id: "x" }];
    expect(meatRuleHint(planned, "2026-10-27", "fleisch")).toMatch(/Fleischgericht/);
    expect(meatRuleHint(planned, "2026-10-27", "fisch")).toBeNull();
  });
});

describe("14-Tage-Sperre und Gewichtung", () => {
  const stats = new Map<string, CookStats>([
    ["recent", { recipe_id: "recent", last_cooked_on: "2026-10-15", times_cooked: 3, days_since: 8 }],
    ["old", { recipe_id: "old", last_cooked_on: "2026-06-01", times_cooked: 1, days_since: 144 }],
    ["edge", { recipe_id: "edge", last_cooked_on: "2026-10-09", times_cooked: 1, days_since: 14 }],
  ]);

  it("schlägt in den letzten 14 Tagen Gekochtes nie vor", () => {
    const recipes = [r("recent", "vegetarisch"), r("old", "vegetarisch"), r("never", "vegetarisch"), r("edge", "vegetarisch")];
    const ids = suggestionCandidates(recipes, stats, [], "2026-10-26", today).map((c) => c.id);
    expect(ids).not.toContain("recent");
    expect(ids).toEqual(["old", "never", "edge"]);
    for (let i = 0; i < 100; i++) expect(pickSuggestion(recipes, stats, [], "2026-10-26", today)?.id).not.toBe("recent");
  });

  it("schlägt nichts doppelt in derselben Woche vor", () => {
    const ids = suggestionCandidates([r("a", "vegetarisch"), r("b", "fisch")], new Map(), [{ date: "2026-10-26", diet: "vegetarisch", recipe_id: "a" }], "2026-10-27", today).map((c) => c.id);
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

describe("Mittag und Abend", () => {
  it("ordnet Slots als Mo mittag < Mo abend < Di mittag", async () => {
    const { slotKey } = await import("../lib/meals");
    expect(slotKey("2026-10-26", "mittag") < slotKey("2026-10-26", "abend")).toBe(true);
    expect(slotKey("2026-10-26", "abend") < slotKey("2026-10-27", "mittag")).toBe(true);
  });

  it("Fleischregel gilt über Mittag und Abend hinweg", async () => {
    const { slotKey } = await import("../lib/meals");
    const planned = [{ date: slotKey("2026-10-26", "mittag"), diet: "fleisch" as Diet, recipe_id: "x" }];
    // Mo abend liegt direkt nach Mo mittag → kein zweites Fleischgericht
    expect(addingViolatesMeatRule(planned, { date: slotKey("2026-10-26", "abend"), diet: "fleisch" })).toBe(true);
    // Di abend: dazwischen ein vegetarisches Mo abend + Di mittag → Fenster Mo abend, Di mittag, Di abend ok
    const more = [...planned, { date: slotKey("2026-10-26", "abend"), diet: "vegetarisch" as Diet, recipe_id: "y" }, { date: slotKey("2026-10-27", "mittag"), diet: "fisch" as Diet, recipe_id: "z" }];
    expect(addingViolatesMeatRule(more, { date: slotKey("2026-10-27", "abend"), diet: "fleisch" })).toBe(false);
  });
});
