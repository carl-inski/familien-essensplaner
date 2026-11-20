import type { Attendance, Meal, MealPlanEntry } from "./types";

export const ALL_MEALS = ["fruehstueck", "mittag", "abend", "snack"] as const;
export const MEALS: Meal[] = ["mittag", "abend"];

export const MEAL_LABEL: Record<Meal, string> = {
  fruehstueck: "Frühstück",
  mittag: "Mittag",
  abend: "Abend",
  snack: "Snack",
};

export function isConfiguredMeal(entry: MealPlanEntry): boolean {
  return entry.status !== "geplant" || !!(
    entry.recipe_id || entry.leftover_of || entry.note || entry.cook_id || entry.cook2_id ||
    entry.servings_override != null || entry.shopped_at || (entry.family_guests ?? 0) > 0
  );
}

/** Mahlzeiten mit einem Eintrag oder einer tagesbezogenen Anwesenheit. */
export function configuredMeals(date: string, plan: MealPlanEntry[], attendance: Attendance[]): Meal[] {
  return ALL_MEALS.filter((meal) =>
    plan.some((entry) => entry.date === date && entry.meal === meal && isConfiguredMeal(entry)) ||
    attendance.some((entry) => entry.date === date && entry.meal === meal),
  );
}

/** Sortierbarer Schlüssel eines Slots, z. B. "2026-10-26#1" für Montag mittag */
export function slotKey(date: string, meal: Meal): string {
  return `${date}#${ALL_MEALS.indexOf(meal)}`;
}
