// Rezept-Schnittstelle für externe Assistenten (POST/GET /api/rezepte).
// Reine, testbare Logik; die Datenbank steckt hinter RecipeStore.

import { timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { deriveDiet, parseNutrition, parseRecipeCollection, parseTimeMinutes, slugifyTag, type RecipeDraft } from "../markdown";
import { parseAmount } from "../quantity";
import { draftToIngredientRows, normalizeTitle, recipeRowFor, resolveCookbook } from "../recipe-draft";
import type { Cookbook, Recipe } from "../types";

export { normalizeTitle };

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export type AuthResult = "ok" | "unauthorized" | "not-configured";

/** Bearer-Token prüfen – Vergleich in konstanter Zeit */
export function checkBearer(header: string | null | undefined, expected: string | undefined): AuthResult {
  if (!expected || !expected.trim()) return "not-configured";
  const m = header?.match(/^Bearer\s+(\S+)\s*$/i);
  if (!m) return "unauthorized";
  const a = Buffer.from(m[1]);
  const b = Buffer.from(expected.trim());
  // timingSafeEqual verlangt gleiche Länge; die Länge selbst verrät bei einem
  // langen Zufallstoken nichts Verwertbares
  if (a.length !== b.length) return "unauthorized";
  return timingSafeEqual(a, b) ? "ok" : "unauthorized";
}

// ---------------------------------------------------------------------------
// Eingabe: Markdown oder JSON
// ---------------------------------------------------------------------------

const text = z.string().trim().min(1);

export const RezeptJsonSchema = z
  .object({
    titel: text.max(200),
    untertitel: z.string().nullish(),
    quelle: z.string().nullish(),
    kochbuch: z.object({ titel: text, seite: z.number().int().positive().nullish() }).nullish(),
    kategorien: z.array(text).nullish(),
    tags: z.array(text).nullish(),
    ernaehrung: z.enum(["vegetarisch", "fisch", "fleisch"]).nullish(),
    zeit: z.string().nullish(),
    portionen: z.number().int().positive().nullish(),
    portionen_text: z.string().nullish(),
    zutaten: z.array(z.object({ gruppe: z.string().nullish(), name: text, menge: z.string().nullish() })).nullish(),
    schritte: z.array(text).nullish(),
    tipp: z.string().nullish(),
    naehrwerte: z.string().nullish(),
    bild_url: z.string().nullish(),
  })
  // household_id & Co. werden still verworfen (zod entfernt unbekannte Felder)
  .refine((r) => (r.zutaten?.length ?? 0) > 0 || !!r.kochbuch, { message: "Mindestens eine Zutat oder ein Kochbuch-Verweis nötig" });

export type RezeptJson = z.infer<typeof RezeptJsonSchema>;

export const PayloadJsonSchema = z.object({ rezepte: z.array(z.unknown()).min(1).max(50) });

const clean = (s: string | null | undefined) => (s && s.trim() ? s.trim() : null);

/** JSON-Rezept → derselbe Entwurf, den der Markdown-Parser liefert */
export function jsonToDraft(j: RezeptJson): RecipeDraft {
  const ingredients = (j.zutaten ?? []).map((z) => {
    const amount_text = clean(z.menge);
    return { group_name: clean(z.gruppe), name: z.name.trim(), amount_text, ...parseAmount(amount_text) };
  });
  const categories = (j.kategorien ?? []).map((c) => c.trim());
  const zeit = clean(j.zeit);
  const naehrwerte = clean(j.naehrwerte);
  const bild = clean(j.bild_url);
  return {
    title: j.titel.trim(),
    subtitle: clean(j.untertitel),
    source: clean(j.quelle),
    cookbook: j.kochbuch ? { title: j.kochbuch.titel.trim(), page: j.kochbuch.seite ?? null } : null,
    categories,
    tags: j.tags?.length ? j.tags.map(slugifyTag).filter(Boolean) : categories.map(slugifyTag).filter(Boolean),
    diet: j.ernaehrung ?? deriveDiet(categories, ingredients.map((i) => i.name)),
    time_text: zeit,
    time_min: parseTimeMinutes(zeit),
    servings: j.portionen ?? null,
    servings_text: clean(j.portionen_text) ?? (j.portionen ? String(j.portionen) : null),
    ingredients,
    steps: (j.schritte ?? []).map((s) => s.trim()),
    tip: clean(j.tipp),
    nutrition: naehrwerte ? parseNutrition(naehrwerte) : null,
    extra_meta: { lines: [] },
    image_url: bild && /^https?:\/\//i.test(bild) ? bild : null,
  };
}

export interface ParseResult {
  drafts: RecipeDraft[];
  /** Rezepte, die schon beim Einlesen scheitern */
  errors: { titel: string; fehler: string }[];
}

/** Body je nach Content-Type als Markdown oder JSON lesen */
export function parsePayload(contentType: string | null, body: string): ParseResult {
  if (contentType?.toLowerCase().includes("application/json")) {
    let json: unknown;
    try {
      json = JSON.parse(body);
    } catch {
      return { drafts: [], errors: [{ titel: "–", fehler: "Ungültiges JSON" }] };
    }
    const payload = PayloadJsonSchema.safeParse(json);
    if (!payload.success) return { drafts: [], errors: [{ titel: "–", fehler: 'Erwartet { "rezepte": [ … ] } mit 1 bis 50 Rezepten' }] };
    const result: ParseResult = { drafts: [], errors: [] };
    payload.data.rezepte.forEach((raw, i) => {
      const r = RezeptJsonSchema.safeParse(raw);
      if (r.success) result.drafts.push(jsonToDraft(r.data));
      else {
        const titel = typeof (raw as { titel?: unknown })?.titel === "string" ? (raw as { titel: string }).titel : `Rezept ${i + 1}`;
        result.errors.push({ titel, fehler: r.error.issues.map((x) => `${x.path.join(".") || "rezept"}: ${x.message}`).join("; ") });
      }
    });
    return result;
  }
  const drafts = parseRecipeCollection(body);
  if (!drafts.length) return { drafts: [], errors: [{ titel: "–", fehler: "Kein Rezept gefunden (erwartet: ## Titel, ### Zutaten, ### Zubereitung)" }] };
  if (drafts.length > 50) return { drafts: [], errors: [{ titel: "–", fehler: "Höchstens 50 Rezepte pro Anfrage" }] };
  const result: ParseResult = { drafts: [], errors: [] };
  for (const d of drafts) {
    if (!d.ingredients.length && !d.cookbook) result.errors.push({ titel: d.title, fehler: "Mindestens eine Zutat oder ein Kochbuch-Verweis nötig" });
    else result.drafts.push(d);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Planen und Schreiben
// ---------------------------------------------------------------------------

export type Modus = "neu" | "ueberspringen" | "ueberschreiben";
export const MODI: Modus[] = ["neu", "ueberspringen", "ueberschreiben"];

export function parseModus(v: string | null): Modus | null {
  if (!v) return "neu";
  return (MODI as string[]).includes(v) ? (v as Modus) : null;
}

export type Status = "angelegt" | "aktualisiert" | "uebersprungen" | "duplikat" | "fehler";

export interface Ergebnis {
  titel: string;
  status: Status;
  id: string | null;
  url: string | null;
  fehler?: string;
  /** nur bei dry_run: was geschrieben würde */
  entwurf?: RecipeDraft;
  kochbuch?: string | null;
}

export interface RecipeStore {
  snapshot(): Promise<{ recipes: Recipe[]; cookbooks: Cookbook[] }>;
  save(input: {
    recipe: ReturnType<typeof recipeRowFor>;
    ingredients: Omit<ReturnType<typeof draftToIngredientRows>[number], "recipe_id">[];
    existingId: string | null;
    createCookbook: string | null;
  }): Promise<string>;
}

const url = (id: string) => `/rezepte/${id}`;

export async function importRecipes(
  store: RecipeStore,
  parsed: ParseResult,
  modus: Modus,
  dryRun: boolean,
): Promise<{ status: number; body: { ergebnisse: Ergebnis[]; dry_run?: true } }> {
  const { recipes, cookbooks } = await store.snapshot();
  const known = new Map(recipes.map((r) => [normalizeTitle(r.title), r.id]));
  const ergebnisse: Ergebnis[] = parsed.errors.map((e) => ({ titel: e.titel, status: "fehler", id: null, url: null, fehler: e.fehler }));
  const seen = new Set<string>();

  for (const draft of parsed.drafts) {
    const key = normalizeTitle(draft.title);
    if (seen.has(key)) {
      ergebnisse.push({ titel: draft.title, status: "fehler", id: null, url: null, fehler: "Kommt im selben Stapel doppelt vor" });
      continue;
    }
    seen.add(key);
    const existingId = known.get(key) ?? null;
    const book = resolveCookbook(draft, cookbooks);
    const bookLabel = book ? book.match?.title ?? book.create : null;

    if (existingId && modus === "neu") {
      ergebnisse.push({ titel: draft.title, status: "duplikat", id: existingId, url: url(existingId), fehler: "Rezept mit diesem Namen gibt es schon" });
      continue;
    }
    if (existingId && modus === "ueberspringen") {
      ergebnisse.push({ titel: draft.title, status: "uebersprungen", id: existingId, url: url(existingId) });
      continue;
    }
    const status: Status = existingId ? "aktualisiert" : "angelegt";
    if (dryRun) {
      ergebnisse.push({ titel: draft.title, status, id: existingId, url: existingId ? url(existingId) : null, entwurf: draft, kochbuch: bookLabel });
      continue;
    }
    try {
      const recipe = recipeRowFor(draft, book?.match?.id ?? null, !!book?.confirmed);
      // Neues Buch: unbestätigt verknüpfen (die RPC legt es an)
      if (book?.create) recipe.cookbook_link_confirmed = false;
      const ingredients = draftToIngredientRows(draft, "").map((row) => {
        const { recipe_id, ...rest } = row;
        void recipe_id;
        return rest;
      });
      const id = await store.save({ recipe, ingredients, existingId, createCookbook: book?.create ?? null });
      ergebnisse.push({ titel: draft.title, status, id, url: url(id) });
    } catch (e) {
      ergebnisse.push({ titel: draft.title, status: "fehler", id: null, url: null, fehler: (e as Error).message });
    }
  }

  // 201: etwas angelegt · 409: nichts geschrieben, aber Duplikate (Modus „neu“)
  // 422: alles fehlerhaft · sonst 200
  const has = (st: Status) => ergebnisse.some((e) => e.status === st);
  let status = 200;
  if (!dryRun) {
    if (has("angelegt")) status = 201;
    else if (!has("aktualisiert") && has("duplikat")) status = 409;
    else if (ergebnisse.length && ergebnisse.every((e) => e.status === "fehler")) status = 422;
  }
  return { status, body: dryRun ? { ergebnisse, dry_run: true } : { ergebnisse } };
}

/** Kurzliste für GET /api/rezepte */
export function recipeSummaries(recipes: Recipe[], cookbooks: Cookbook[]) {
  const byId = new Map(cookbooks.map((c) => [c.id, c.title]));
  return recipes.map((r) => ({
    id: r.id,
    title: r.title,
    updated_at: r.updated_at,
    servings: r.servings,
    cookbook_title: r.cookbook_id ? byId.get(r.cookbook_id) ?? null : null,
  }));
}
