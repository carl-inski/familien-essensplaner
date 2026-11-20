// Regelbasierte Vorschläge (Briefing 4.3, 4.7)
// - nicht in den letzten 14 Tagen gekocht
// - je länger nicht gekocht, desto höher gewichtet; nie gekocht leicht bevorzugt; eigene Kochbücher bevorzugt

import { daysBetween } from "./dates";
import type { CookStats, Meal } from "./types";

export const BLOCK_DAYS = 14;

// Snacks, Süßes und Gebäck sind keine Abendessen-Vorschläge
const SNACK_TAGS = ["snack", "süß", "dessert", "backen", "kuchen"];
const NOT_DINNER = [...SNACK_TAGS, "frühstück", "getränk"];

export function isDinnerCandidate(r: { tags: string[]; categories: string[] }): boolean {
  const words = [...r.tags, ...r.categories].map((t) => t.toLowerCase());
  return !words.some((w) => NOT_DINNER.includes(w));
}

export function isMealCandidate(recipe: { tags: string[]; categories: string[] }, meal: Meal): boolean {
  if (meal === "mittag" || meal === "abend") return isDinnerCandidate(recipe);
  const tags = [...recipe.tags, ...recipe.categories].map((tag) => tag.toLowerCase());
  if (meal === "fruehstueck") return tags.includes("frühstück");
  return tags.some((tag) => SNACK_TAGS.includes(tag));
}

export interface SuggestRecipe {
  id: string;
  cookbook_id: string | null;
}

export interface PlannedDish {
  date: string;
  recipe_id: string | null;
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

export function suggestionCandidates<R extends SuggestRecipe>(
  recipes: R[],
  stats: Map<string, CookStats>,
  planned: PlannedDish[],
  today: string,
): R[] {
  const plannedIds = new Set(planned.map((p) => p.recipe_id).filter(Boolean));
  return recipes.filter((recipe) => !plannedIds.has(recipe.id) && !isBlocked(stats.get(recipe.id), today));
}

export function pickSuggestion(
  recipes: SuggestRecipe[],
  stats: Map<string, CookStats>,
  planned: PlannedDish[],
  today: string,
  random: () => number = Math.random,
): SuggestRecipe | null {
  const candidates = suggestionCandidates(recipes, stats, planned, today);
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

/** Kandidaten für einen offenen Slot, nach Gewicht sortiert (länger nicht gekocht zuerst) */
export function rankedCandidates<R extends SuggestRecipe & { tags: string[]; categories: string[] }>(
  recipes: R[],
  stats: Map<string, CookStats>,
  planned: PlannedDish[],
  today: string,
  opts: { dinner?: boolean; exclude?: Set<string> } = {},
): R[] {
  const pool = recipes.filter((r) => !opts.exclude?.has(r.id) && (!opts.dinner || isDinnerCandidate(r)));
  return suggestionCandidates(pool, stats, planned, today).sort(
    (a, b) => weight(b, stats.get(b.id), today) - weight(a, stats.get(a.id), today),
  );
}

export interface BatchProblem {
  slot: string;
  problem: string | null;
}

/**
 * Prüft mehrere Vorschläge nacheinander gegen Plan und Kochhistorie.
 * Bereits geprüfte Einträge des Stapels zählen für die folgenden mit.
 */
export function checkBatch(
  items: { slot: string; recipe_id: string }[],
  planned: PlannedDish[],
  stats: Map<string, CookStats>,
  today: string,
): BatchProblem[] {
  const accepted: PlannedDish[] = [];
  return [...items]
    .sort((a, b) => a.slot.localeCompare(b.slot))
    .map((it) => {
      const others = [...planned, ...accepted].filter((p) => p.date !== it.slot && p.recipe_id);
      let problem: string | null = null;
      if (others.some((p) => p.recipe_id === it.recipe_id)) problem = "Steht in dieser Zeit schon im Plan.";
      else if (isBlocked(stats.get(it.recipe_id), today)) problem = `Vor weniger als ${BLOCK_DAYS} Tagen gekocht.`;
      if (!problem) accepted.push({ date: it.slot, recipe_id: it.recipe_id });
      return { slot: it.slot, problem };
    });
}
