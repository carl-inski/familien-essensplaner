// Umwandlung zwischen Datenbank-Rezept und Markdown-Entwurf

import type { MetaLine, RecipeDraft } from "./markdown";
import type { Cookbook, Recipe } from "./types";

export function recipeToDraft(r: Recipe, cookbooksById: Map<string, Cookbook>): RecipeDraft {
  const book = r.cookbook_id ? cookbooksById.get(r.cookbook_id) : null;
  const extra = (r.extra_meta as { lines?: MetaLine[] } | null)?.lines ?? [];
  return {
    title: r.title,
    subtitle: r.subtitle,
    source: r.source,
    cookbook: book ? { title: book.title, page: r.cookbook_page } : null,
    categories: r.categories,
    tags: r.tags,
    diet: r.diet ?? "vegetarisch",
    time_text: r.time_text,
    time_min: r.time_min,
    servings: r.servings,
    servings_text: r.servings_text,
    ingredients: (r.ep_recipe_ingredients ?? [])
      .slice()
      .sort((a, b) => a.position - b.position)
      .map((i) => ({ group_name: i.group_name, name: i.name, amount: i.amount === null ? null : Number(i.amount), unit: i.unit, amount_text: i.amount_text })),
    steps: r.steps,
    tip: r.tip,
    nutrition: r.nutrition as RecipeDraft["nutrition"],
    extra_meta: { lines: extra },
  };
}

/** Spalten für ep_recipes aus einem Entwurf (ohne Kochbuch-Zuordnung) */
export function draftToRecipeRow(d: RecipeDraft) {
  return {
    title: d.title,
    subtitle: d.subtitle,
    source: d.source,
    categories: d.categories,
    tags: d.tags,
    diet: d.diet,
    time_text: d.time_text,
    time_min: d.time_min,
    servings: d.servings,
    servings_text: d.servings_text,
    steps: d.steps,
    tip: d.tip,
    nutrition: d.nutrition,
    extra_meta: d.extra_meta,
  };
}

export function draftToIngredientRows(d: RecipeDraft, recipeId: string) {
  return d.ingredients.map((i, position) => ({
    recipe_id: recipeId,
    position,
    group_name: i.group_name,
    name: i.name,
    amount: i.amount,
    unit: i.unit,
    amount_text: i.amount_text,
  }));
}

/** Unscharfer Abgleich eines Buchtitels gegen das Regal */
export function matchCookbook(title: string, cookbooks: Cookbook[]): Cookbook | null {
  const norm = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  const t = norm(title);
  if (!t) return null;
  return (
    cookbooks.find((c) => norm(c.title) === t) ??
    cookbooks.find((c) => norm(c.title).includes(t) || t.includes(norm(c.title))) ??
    null
  );
}

/** Kennt Titel oder Quelle ein Buch aus dem Regal (z. B. "Jamie Oliver", "Leon")? */
export function suggestCookbook(d: Pick<RecipeDraft, "title" | "source">, cookbooks: Cookbook[]): Cookbook | null {
  const hay = `${d.title} ${d.source ?? ""}`.toLowerCase();
  for (const c of cookbooks) {
    const hints = [c.title, ...c.authors].map((h) => h.toLowerCase()).filter((h) => h.length >= 4);
    if (hints.some((h) => hay.includes(h))) return c;
  }
  return null;
}
