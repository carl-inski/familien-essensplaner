// Mahlzeiten pro Tag: Mittag- und Abendessen

import type { Meal } from "./types";

export const MEALS: Meal[] = ["mittag", "abend"];

export const MEAL_LABEL: Record<Meal, string> = { fruehstueck: "Frühstück", mittag: "Mittag", abend: "Abend" };

const ORDER: Record<Meal, number> = { fruehstueck: 0, mittag: 1, abend: 2 };

/** Sortierbarer Schlüssel eines Slots, z. B. "2026-10-26#1" für Montag mittag */
export function slotKey(date: string, meal: Meal): string {
  return `${date}#${ORDER[meal]}`;
}
