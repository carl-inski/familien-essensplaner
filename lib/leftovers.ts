// „Was koche ich damit?“ – Rezepte nach vorhandenen Zutaten bewerten (ohne KI).

import { normalizeName } from "./quantity";

/** Grober Wortstamm: „Zucchini“, „Tomaten“ → „tomat“, „Kartoffeln“ → „kartoffel“ */
export function stem(word: string): string {
  return normalizeName(word)
    .replace(/\(.*?\)/g, "")
    .replace(/[^\p{L}\s-]/gu, " ")
    .trim()
    .replace(/(innen|en|n|e|s)$/u, "");
}

export interface IngredientMatch<R> {
  recipe: R;
  matched: string[];
  /** Zutaten des Rezepts, die nicht genannt wurden */
  missing: number;
}

export function matchByIngredients<R extends { ep_recipe_ingredients?: { name: string }[] }>(recipes: R[], available: string[], limit = 8): IngredientMatch<R>[] {
  const wanted = available.map((a) => ({ raw: a.trim(), s: stem(a) })).filter((w) => w.s.length >= 3);
  const out: IngredientMatch<R>[] = [];
  for (const recipe of recipes) {
    const names = (recipe.ep_recipe_ingredients ?? []).map((i) => normalizeName(i.name));
    if (!names.length) continue;
    const matched = wanted.filter((w) => names.some((n) => n.includes(w.s))).map((w) => w.raw);
    if (!matched.length) continue;
    const used = names.filter((n) => wanted.some((w) => n.includes(w.s))).length;
    out.push({ recipe, matched, missing: names.length - used });
  }
  return out.sort((a, b) => b.matched.length - a.matched.length || a.missing - b.missing).slice(0, limit);
}
