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

/**
 * Titel für den Duplikat-Abgleich: klein, „&“ = „und“, Satzzeichen und
 * Mehrfach-Leerzeichen raus. Klammerzusätze bleiben als Wörter erhalten.
 * „Ofenlachs mit Brokkoli, Kartoffeln & Feta-Joghurt“ = „… Kartoffeln und Feta-Joghurt“.
 */
export function normalizeTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/&/g, " und ")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

export interface CookbookChoice {
  /** vorhandenes Buch im Regal */
  match: Cookbook | null;
  /** neues Buch mit diesem Titel anlegen */
  create: string | null;
  /** Verknüpfung gilt als bestätigt */
  confirmed: boolean;
}

/**
 * Kochbuch für einen Entwurf: „**Kochbuch:**“ gegen das Regal abgleichen
 * (Treffer = bestätigt, sonst neues Buch zum Bestätigen); ohne Angabe nur ein
 * unbestätigter Vorschlag über Titel/Quelle.
 */
export function resolveCookbook(d: Pick<RecipeDraft, "title" | "source" | "cookbook">, cookbooks: Cookbook[]): CookbookChoice | null {
  if (d.cookbook) {
    const match = matchCookbook(d.cookbook.title, cookbooks);
    return { match, create: match ? null : d.cookbook.title, confirmed: !!match };
  }
  const hint = suggestCookbook(d, cookbooks);
  return hint ? { match: hint, create: null, confirmed: false } : null;
}

/** Spalten für ep_recipes inkl. Kochbuch-Verknüpfung und (nur http/https) Bild */
export function recipeRowFor(d: RecipeDraft, cookbookId: string | null, confirmed: boolean) {
  return {
    ...draftToRecipeRow(d),
    cookbook_id: cookbookId,
    cookbook_page: cookbookId ? d.cookbook?.page ?? null : null,
    cookbook_link_confirmed: cookbookId ? confirmed : true,
    image_url: d.image_url && /^https?:\/\//i.test(d.image_url) ? d.image_url : null,
  };
}
