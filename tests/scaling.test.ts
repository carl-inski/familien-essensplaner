import { describe, expect, it } from "vitest";
import { buildShoppingList, eaters, scaleIngredients, servingsFor } from "../lib/planning";
import { formatAmount, parseAmount, scaleAmount } from "../lib/quantity";
import type { Attendance, Ingredient, MealPlanEntry, Member, Recipe } from "../lib/types";

const ing = (name: string, amount_text: string, position = 0): Ingredient => ({
  position,
  group_name: null,
  name,
  amount_text,
  ...parseAmount(amount_text),
});

const member = (id: string, default_week = {}): Member => ({
  id, household_id: "h", name: id, email: null, user_id: null, role: "member", default_week, position: 0,
});

describe("Mengen-Parsing", () => {
  it("versteht Dezimalkomma, Spannen, Brüche und Einheiten", () => {
    expect(parseAmount("1,5 EL")).toEqual({ amount: 1.5, unit: "EL" });
    expect(parseAmount("1–1,2 l")).toEqual({ amount: 1.2, unit: "l" });
    expect(parseAmount("½ Kopf")).toEqual({ amount: 0.5, unit: "Kopf" });
    expect(parseAmount("2 Zehen")).toEqual({ amount: 2, unit: "Zehen" });
    expect(parseAmount("2 Packungen")).toEqual({ amount: 2, unit: "Pck." });
    expect(parseAmount("4 mittelgroße")).toEqual({ amount: 4, unit: null });
    expect(parseAmount("nach Geschmack")).toEqual({ amount: null, unit: null });
  });
});

describe("Portionsskalierung (Abschnitt 7)", () => {
  it("4 Portionen, 1 kg Hähnchen, 3 Personen → 750 g", () => {
    const [h] = scaleIngredients([ing("Hähnchen", "1 kg")], 4, 3);
    expect(formatAmount(h.scaled_amount, h.scaled_unit)).toBe("750 g");
  });

  it("5 Personen, 2 Orangen → 3 Orangen (2,5 aufgerundet)", () => {
    const [o] = scaleIngredients([ing("Orangen", "2")], 4, 5);
    expect(o.scaled_amount).toBe(3);
  });

  it("rundet g/ml auf 5 bzw. 10 und EL/TL auf 0,5", () => {
    expect(scaleAmount(75, "ml", 1.25)).toEqual({ amount: 95, unit: "ml" }); // 93,75
    expect(scaleAmount(240, "g", 1.25)).toEqual({ amount: 300, unit: "g" });
    expect(scaleAmount(1, "TL", 1.2)).toEqual({ amount: 1, unit: "TL" });
    expect(scaleAmount(2, "EL", 1.25)).toEqual({ amount: 2.5, unit: "EL" });
  });

  it("skaliert Zutaten ohne Menge nicht", () => {
    const [s] = scaleIngredients([ing("Salz, Pfeffer", "nach Geschmack")], 4, 8);
    expect(s.scaled_amount).toBeNull();
    expect(s.text).toBe("Salz, Pfeffer (nach Geschmack)");
  });
});

describe("Esser und Reste", () => {
  const members = [member("a"), member("b"), member("c", { tue: { abend: "weg" } })];
  const attendance: Attendance[] = [
    { id: "1", member_id: "b", date: "2026-10-26", meal: "abend", status: "da", guests: 2 },
    { id: "2", member_id: "a", date: "2026-10-27", meal: "abend", status: "weg", guests: 0 },
  ];

  it("zählt anwesende Personen plus Gäste und beachtet die Standardwoche", () => {
    expect(eaters(members, attendance, "2026-10-26", "abend")).toBe(5); // Mo: a, b+2, c
    expect(eaters(members, attendance, "2026-10-27", "abend")).toBe(1); // Di: a weg, c Standard weg
  });

  it("Reste-Slot erhöht die Portionen des Ursprungs-Slots", () => {
    const plan: MealPlanEntry[] = [
      { id: "p1", household_id: "h", date: "2026-10-26", meal: "abend", recipe_id: "r", leftover_of: null, cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null },
      { id: "p2", household_id: "h", date: "2026-10-27", meal: "abend", recipe_id: null, leftover_of: "p1", cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null },
    ];
    expect(servingsFor(plan[0], plan, members, attendance)).toBe(6);

    const recipe = { id: "r", title: "Chili", servings: 4, ep_recipe_ingredients: [ing("Rinderhack", "500 g"), ing("Salz", "nach Geschmack", 1)] } as Recipe;
    const list = buildShoppingList(plan, new Map([["r", recipe]]), members, attendance);
    expect(list.find((i) => i.name === "Rinderhack")?.text).toBe("750 g Rinderhack");
    expect(list.filter((i) => i.name === "Salz")).toHaveLength(1);
  });

  it("summiert gleiche Zutaten mit gleicher Einheit über die Woche", () => {
    const mk = (id: string, date: string, recipe_id: string): MealPlanEntry => ({ id, household_id: "h", date, meal: "abend", recipe_id, leftover_of: null, cook_id: null, cook2_id: null, servings_override: 4, status: "geplant", note: null });
    const plan = [mk("x", "2026-10-28", "r1"), mk("y", "2026-10-29", "r2")];
    const r1 = { id: "r1", title: "A", servings: 4, ep_recipe_ingredients: [ing("Feta", "200 g")] } as Recipe;
    const r2 = { id: "r2", title: "B", servings: 4, ep_recipe_ingredients: [ing("Feta", "200 g"), ing("Zwiebel", "1")] } as Recipe;
    const list = buildShoppingList(plan, new Map([["r1", r1], ["r2", r2]]), members, []);
    expect(list.find((i) => i.name === "Feta")).toMatchObject({ amount: 400, unit: "g", text: "400 g Feta" });
  });
});
