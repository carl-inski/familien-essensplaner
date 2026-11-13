import { describe, expect, it } from "vitest";
import { applyChange, changeProblem, nextFreeSlot, previewChange, slotName, type ChangeContext, type PlanChange } from "../lib/plan-change";
import { parseAmount } from "../lib/quantity";
import { purchasesFor, shoppingState, type Purchase } from "../lib/shopping";
import type { Attendance, Ingredient, MealPlanEntry, Member, Recipe } from "../lib/types";

// Mittwoch
const TODAY = "2026-11-11";
const NOW = "2026-11-11T17:30:00Z";
const WED = { date: "2026-11-11", meal: "abend" as const };
const FRI = { date: "2026-11-13", meal: "abend" as const };

const ing = (name: string, amount_text: string | null, position = 0): Ingredient => ({ position, group_name: null, name, amount_text, ...parseAmount(amount_text) });
const recipe = (id: string, title: string, ingredients: Ingredient[]): Recipe =>
  ({ id, title, servings: 4, ep_recipe_ingredients: ingredients, diet: "vegetarisch", tags: [], categories: [], cookbook_id: null }) as unknown as Recipe;
const member = (id: string): Member => ({ id, household_id: "h", name: id, email: null, user_id: null, role: "member", default_week: {}, position: 0 });
const entry = (id: string, date: string, recipe_id: string | null, extra: Partial<MealPlanEntry> = {}): MealPlanEntry => ({
  id, household_id: "h", date, meal: "abend", recipe_id, leftover_of: null, cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null, ...extra,
});

const gnocchi = recipe("gn", "Gnocchi", [ing("Gnocchi", "600 g"), ing("Joghurt", "200 g", 1)]);
const curry = recipe("cu", "Curry", [ing("Reis", "400 g"), ing("Joghurt", "100 g", 1)]);
const recipes = new Map([gnocchi, curry].map((r) => [r.id, r]));
const three = ["a", "b", "c"].map(member);
// Freitag kommen zwei Gäste: fünf statt drei
const fridayGuests: Attendance[] = [{ id: "g", member_id: "a", date: FRI.date, meal: "abend", status: "da", guests: 2 }];

const ctx = (plan: MealPlanEntry[], purchases: Purchase[] = [], attendance: Attendance[] = []): ChangeContext => ({ plan, purchases, recipes, members: three, attendance, today: TODAY, now: NOW });

let seq = 0;
/** Alles Offene einkaufen, wie in der App */
function buyAll(c: ChangeContext): Purchase[] {
  const s = shoppingState({ ...c });
  return s.open.flatMap((i) => purchasesFor(i, "h", "a", () => `c${++seq}`)).map((r) => ({ ...r, id: `p-${r.client_id}`, bought_at: NOW }));
}

describe("Der Mittwoch aus der Demo", () => {
  const wed = entry("mi", WED.date, "gn");
  const move: PlanChange = { kind: "verschieben", from: WED, to: FRI };

  it("heute auswärts, Gnocchi auf Freitag, zwei Gäste mehr – nach dem Einkauf", () => {
    const bought = buyAll(ctx([wed])); // für drei: 450 g Gnocchi, 150 g Joghurt
    const p = previewChange(move, ctx([wed], bought, fridayGuests));
    expect(p.problem).toBeNull();
    expect(p.plan).toEqual(["Gnocchi auf Freitag Abend.", "2 Portionen mehr (5 statt 3)."]);
    // 750 − 450 = 300 g Gnocchi, 250 − 150 = 100 g Joghurt
    expect(p.shopping).toEqual(["Zusätzlich auf der Liste: 300 g Gnocchi, 100 g Joghurt."]);
  });

  it("die Käufe wandern mit dem Gericht", () => {
    const bought = buyAll(ctx([wed]));
    const after = applyChange(move, [wed], bought);
    const friday = after.plan.find((e) => e.date === FRI.date)!;
    expect(friday.recipe_id).toBe("gn");
    expect(after.plan.find((e) => e.date === WED.date)!.recipe_id).toBeNull();
    expect(after.purchases.every((x) => x.meal_plan_id === friday.id)).toBe(true);
    // Danach ist für drei nichts offen und nichts „übrig“
    const s = shoppingState({ ...ctx(after.plan, after.purchases) });
    expect(s.open).toEqual([]);
    expect(s.stock).toEqual([]);
  });

  it("gleich viele Esser: nur der Tag ändert sich", () => {
    const p = previewChange(move, ctx([wed], buyAll(ctx([wed]))));
    expect(p.plan).toEqual(["Gnocchi auf Freitag Abend."]);
    expect(p.shopping).toEqual(["Die Einkaufsliste bleibt, wie sie ist."]);
  });

  it("vor dem Einkauf: die Liste wächst nur um die Differenz", () => {
    const p = previewChange(move, ctx([wed], [], fridayGuests));
    expect(p.shopping).toEqual(["Zusätzlich auf der Liste: 300 g Gnocchi, 100 g Joghurt."]);
  });

  it("von Hand gesetzte Portionen gelten am neuen Tag nicht mehr", () => {
    const p = previewChange(move, ctx([{ ...wed, servings_override: 8 }]));
    expect(p.plan).toEqual(["Gnocchi auf Freitag Abend.", "5 Portionen weniger (3 statt 8)."]);
  });
});

describe("Heute auswärts", () => {
  const wed = entry("mi", WED.date, "gn");
  const out: PlanChange = { kind: "auswaerts", slot: WED };

  it("vor dem Einkauf: der Bedarf fällt weg", () => {
    const p = previewChange(out, ctx([wed]));
    expect(p.plan).toEqual(["Gnocchi fällt heute Abend aus."]);
    expect(p.shopping).toEqual(["Nicht mehr nötig: 450 g Gnocchi, 150 g Joghurt."]);
  });

  it("nach dem Einkauf: Gekauftes bleibt da", () => {
    const p = previewChange(out, ctx([wed], buyAll(ctx([wed]))));
    expect(p.shopping).toEqual(["Schon gekauft und bleibt da: 450 g Gnocchi, 150 g Joghurt."]);
  });

  it("was da bleibt, senkt den Bedarf eines anderen Gerichts", () => {
    const fri = entry("fr", FRI.date, "cu"); // braucht 300 g Reis, 75 g Joghurt
    const bought = buyAll(ctx([wed])); // nur für Mittwoch gekauft
    const p = previewChange(out, ctx([wed, fri], bought));
    expect(p.shopping).toEqual(["Nicht mehr nötig: 75 g Joghurt.", "Schon gekauft und bleibt da: 450 g Gnocchi, 150 g Joghurt."]);
  });

  it("Milch für ein anderes Gericht bleibt mit der richtigen Restmenge auf der Liste", () => {
    const fri = entry("fr", FRI.date, "cu");
    const p = previewChange(out, ctx([wed, fri]));
    // Joghurt: vorher 150 + 75 = 225 g, danach nur noch 75 g für Freitag
    expect(p.shopping).toEqual(["Nicht mehr nötig: 150 g Joghurt, 450 g Gnocchi."]);
    const after = applyChange(out, [wed, fri], []);
    expect(shoppingState({ ...ctx(after.plan) }).open.map((i) => i.text).sort()).toEqual(["300 g Reis", "75 g Joghurt"]);
  });
});

describe("Tauschen", () => {
  const wed = entry("mi", WED.date, "gn", { cook_id: "a", note: "früh essen" });
  const fri = entry("fr", FRI.date, "cu", { cook_id: "b" });
  const move: PlanChange = { kind: "verschieben", from: WED, to: FRI };

  it("steht am Ziel schon etwas, tauschen die Gerichte", () => {
    const p = previewChange(move, ctx([wed, fri]));
    expect(p.plan).toEqual(["Gnocchi auf Freitag Abend.", "Curry dafür auf heute Abend."]);
    expect(p.shopping).toEqual(["Die Einkaufsliste bleibt, wie sie ist."]);
  });

  it("Koch und Notiz bleiben beim Tag", () => {
    const after = applyChange(move, [wed, fri], []).plan;
    expect(after.find((e) => e.date === WED.date)).toMatchObject({ recipe_id: "cu", cook_id: "a", note: "früh essen" });
    expect(after.find((e) => e.date === FRI.date)).toMatchObject({ recipe_id: "gn", cook_id: "b", note: null });
  });

  it("Reste zeigen weiter auf dasselbe Gericht", () => {
    const rest = entry("sa", "2026-11-14", null, { leftover_of: "mi" });
    const after = applyChange(move, [wed, fri, rest], []).plan;
    const gnocchiNow = after.find((e) => e.recipe_id === "gn")!;
    expect(after.find((e) => e.id === "sa")!.leftover_of).toBe(gnocchiNow.id);
  });

  it("beide Käufe wandern jeweils mit", () => {
    const bought = buyAll(ctx([wed, fri]));
    const after = applyChange(move, [wed, fri], bought);
    const s = shoppingState({ ...ctx(after.plan, after.purchases) });
    expect(s.open).toEqual([]);
    expect(s.stock).toEqual([]);
  });
});

describe("Was nicht geht", () => {
  const wed = entry("mi", WED.date, "gn");

  it.each([
    [{ kind: "verschieben", from: FRI, to: WED } as PlanChange, "Dort ist nichts geplant."],
    [{ kind: "verschieben", from: WED, to: WED } as PlanChange, "Das Gericht steht schon dort."],
    [{ kind: "verschieben", from: WED, to: { date: "2026-11-10", meal: "abend" } } as PlanChange, "In die Vergangenheit lässt sich nichts verschieben."],
    [{ kind: "auswaerts", slot: { date: "2026-11-10", meal: "abend" } } as PlanChange, "Vergangene Mahlzeiten lassen sich nicht mehr ändern."],
  ])("%j", (change, text) => {
    expect(changeProblem(change, [wed, entry("alt", "2026-11-10", "cu")], TODAY)).toBe(text);
    expect(previewChange(change, ctx([wed, entry("alt", "2026-11-10", "cu")]))).toEqual({ problem: text, plan: [], shopping: [] });
  });

  it("ein Gericht tauscht nicht mit seinen eigenen Resten", () => {
    const rest = entry("fr", FRI.date, null, { leftover_of: "mi" });
    expect(changeProblem({ kind: "verschieben", from: WED, to: FRI }, [wed, rest], TODAY)).toBe("Ein Gericht und seine Reste lassen sich nicht tauschen.");
  });

  it("schon ausgefallen", () => {
    expect(changeProblem({ kind: "auswaerts", slot: WED }, [{ ...wed, status: "ausgefallen" }], TODAY)).toBe("Das Gericht ist schon als ausgefallen markiert.");
  });
});

describe("Hilfen", () => {
  it("benennt Mahlzeiten, wie man sie sagt", () => {
    expect(slotName(WED, TODAY)).toBe("heute Abend");
    expect(slotName({ date: "2026-11-12", meal: "mittag" }, TODAY)).toBe("morgen Mittag");
    expect(slotName(FRI, TODAY)).toBe("Freitag Abend");
    expect(slotName({ date: "2026-11-20", meal: "abend" }, TODAY)).toBe("Fr 20.11. Abend");
  });

  it("findet den nächsten freien Abend", () => {
    const plan = [entry("mi", WED.date, "gn"), entry("do", "2026-11-12", "cu"), entry("fr", FRI.date, null, { note: "nur Notiz" })];
    expect(nextFreeSlot(plan, WED, TODAY)).toEqual(FRI);
  });
});
