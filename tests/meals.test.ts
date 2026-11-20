import { describe, expect, it } from "vitest";
import { configuredMeals, slotKey } from "../lib/meals";
import type { MealPlanEntry } from "../lib/types";

const date = "2026-11-16";
const entry = (meal: MealPlanEntry["meal"], fields: Partial<MealPlanEntry> = {}): MealPlanEntry => ({
  id: meal, household_id: "family", date, meal, recipe_id: null, leftover_of: null, cook_id: null,
  cook2_id: null, servings_override: null, status: "geplant", note: null, ...fields,
});

describe("meals in the weekly plan", () => {
  it("shows saved plans and explicit attendance in meal order, skipping unused slots", () => {
    const plan = [
      entry("abend"),
      entry("snack", { note: "Nach der Schule" }),
      entry("mittag", { status: "ausgefallen" }),
      entry("abend", { date: "2026-11-17", recipe_id: "recipe" }),
    ];
    const attendance = [{ id: "a", member_id: "member", date, meal: "fruehstueck", status: "weg", guests: 0 }] as const;
    expect(configuredMeals(date, plan, [...attendance])).toEqual(["fruehstueck", "mittag", "snack"]);
  });

  it("sorts breakfast, lunch, dinner and snack within a date", () => {
    const order = ["snack", "mittag", "fruehstueck", "abend"] as const;
    expect(order.map((meal) => slotKey(date, meal)).sort()).toEqual([0, 1, 2, 3].map((position) => `${date}#${position}`));
  });
});
