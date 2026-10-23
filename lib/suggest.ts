// Regelbasierte Vorschläge (Briefing 4.3, 4.7)
// - nicht in den letzten 14 Tagen gekocht
// - höchstens 1 Fleischgericht pro 3 aufeinanderfolgende Gerichte (Fisch zählt nicht)
// - je länger nicht gekocht, desto höher gewichtet; nie gekocht leicht bevorzugt; eigene Kochbücher bevorzugt

import { daysBetween } from "./dates";
import type { CookStats, Diet } from "./types";

export const BLOCK_DAYS = 14;

// Snacks, Süßes und Gebäck sind keine Abendessen-Vorschläge
const NOT_DINNER = ["snack", "süß", "dessert", "backen", "kuchen", "frühstück", "getränk"];

export function isDinnerCandidate(r: { tags: string[]; categories: string[] }): boolean {
  const words = [...r.tags, ...r.categories].map((t) => t.toLowerCase());
  return !words.some((w) => NOT_DINNER.includes(w));
}

export interface SuggestRecipe {
  id: string;
  diet: Diet | null;
  cookbook_id: string | null;
}

export interface PlannedDish {
  date: string;
  diet: Diet | null;
  recipe_id: string | null;
}

/** true, wenn in irgendeinem Fenster aus 3 aufeinanderfolgenden Gerichten mehr als 1 Fleischgericht liegt */
export function violatesMeatRule(dishes: { date: string; diet: Diet | null }[]): boolean {
  const sorted = [...dishes].sort((a, b) => a.date.localeCompare(b.date));
  for (let i = 0; i < sorted.length; i++) {
    const window = sorted.slice(i, i + 3);
    if (window.filter((d) => d.diet === "fleisch").length > 1) return true;
  }
  return false;
}

/** Prüft nur die Fenster, die das neue Gericht enthalten – bestehende manuelle Verstöße blockieren keine Vorschläge. */
export function addingViolatesMeatRule(others: { date: string; diet: Diet | null }[], dish: { date: string; diet: Diet | null }): boolean {
  if (dish.diet !== "fleisch") return false;
  const sorted = [...others, { ...dish, isNew: true }].sort((a, b) => a.date.localeCompare(b.date));
  const idx = sorted.findIndex((d) => "isNew" in d);
  for (let start = Math.max(0, idx - 2); start <= idx; start++) {
    const window = sorted.slice(start, start + 3);
    if (window.length && window.filter((d) => d.diet === "fleisch").length > 1) return true;
  }
  return false;
}

export function isBlocked(stats: CookStats | undefined, today: string): boolean {
  if (!stats) return false;
  return daysBetween(stats.last_cooked_on, today) < BLOCK_DAYS;
}

export function weight(recipe: SuggestRecipe, stats: CookStats | undefined, today: string): number {
  // nie gekocht: etwas mehr als "sehr lange her"
  let w = stats ? Math.min(daysBetween(stats.last_cooked_on, today), 120) : 140;
  if (recipe.cookbook_id) w *= 1.3;
  return Math.max(w, 1);
}

export function suggestionCandidates(
  recipes: SuggestRecipe[],
  stats: Map<string, CookStats>,
  planned: PlannedDish[],
  slotDate: string,
  today: string,
): SuggestRecipe[] {
  const plannedIds = new Set(planned.map((p) => p.recipe_id).filter(Boolean));
  const others = planned.filter((p) => p.date !== slotDate && p.recipe_id);
  return recipes.filter((r) => {
    if (plannedIds.has(r.id)) return false;
    if (isBlocked(stats.get(r.id), today)) return false;
    return !addingViolatesMeatRule(others, { date: slotDate, diet: r.diet });
  });
}

export function pickSuggestion(
  recipes: SuggestRecipe[],
  stats: Map<string, CookStats>,
  planned: PlannedDish[],
  slotDate: string,
  today: string,
  random: () => number = Math.random,
): SuggestRecipe | null {
  const candidates = suggestionCandidates(recipes, stats, planned, slotDate, today);
  if (!candidates.length) return null;
  const weights = candidates.map((r) => weight(r, stats.get(r.id), today));
  const total = weights.reduce((a, b) => a + b, 0);
  let x = random() * total;
  for (let i = 0; i < candidates.length; i++) {
    x -= weights[i];
    if (x <= 0) return candidates[i];
  }
  return candidates[candidates.length - 1];
}

/** Hinweis beim manuellen Einplanen (kein Verbot) */
export function meatRuleHint(planned: PlannedDish[], slotDate: string, diet: Diet | null): string | null {
  const others = planned.filter((p) => p.date !== slotDate && p.recipe_id);
  if (addingViolatesMeatRule(others, { date: slotDate, diet })) {
    return "Mehr als 1 Fleischgericht in 3 Gerichten – die Hausregel wäre verletzt.";
  }
  return null;
}
