// Zod-Schemas für strukturierte KI-Antworten und ihre Umwandlung in App-Typen.
// Die Schemas sind bewusst flach und anbieterneutral (auch für OpenRouter-Modelle).

import { z } from "zod";
import { deriveDiet, parseNutrition, parseTimeMinutes, slugifyTag, type RecipeDraft } from "../markdown";
import { parseAmount } from "../quantity";

export const RecipeExtractSchema = z.object({
  is_recipe: z.boolean().describe("false, wenn auf der Quelle kein Rezept erkennbar ist"),
  title: z.string().describe("Rezepttitel auf Deutsch"),
  subtitle: z.string().nullable().describe("kurzer Untertitel, falls vorhanden"),
  servings: z.number().int().nullable().describe("Anzahl Portionen als Zahl"),
  servings_text: z.string().nullable().describe("Portionsangabe wie im Original, z. B. '4 (2 Pizzen)'"),
  time_text: z.string().nullable().describe("Zeitangabe, z. B. 'Vorbereitung 15 Min. / Garzeit 30 Min.'"),
  time_min: z.number().int().nullable().describe("Gesamtzeit in Minuten"),
  diet: z.enum(["vegetarisch", "fisch", "fleisch"]),
  categories: z.array(z.string()).describe("1–3 Kategorien wie 'Pasta', 'Suppe', 'Curry'"),
  ingredients: z.array(
    z.object({
      group: z.string().nullable().describe("Zwischenüberschrift wie 'Teig' oder 'Sauce', sonst null"),
      amount: z.string().nullable().describe("Menge mit Einheit, z. B. '200 g', '2 EL', '1 Prise'; null wenn keine"),
      name: z.string().describe("Zutat ohne Menge, z. B. 'Zwiebeln, fein gewürfelt'"),
    }),
  ),
  steps: z.array(z.string()).describe("Zubereitungsschritte in Reihenfolge, ohne Nummern"),
  tip: z.string().nullable(),
  nutrition_text: z.string().nullable().describe("Nur wenn im Original angegeben, Format '442 kcal | Fett 23,7 g | Eiweiß 42 g'"),
  cookbook_title: z.string().nullable().describe("Buchtitel, falls auf dem Foto erkennbar"),
  cookbook_page: z.number().int().nullable().describe("Seitenzahl, falls auf dem Foto erkennbar"),
});

export type RecipeExtract = z.infer<typeof RecipeExtractSchema>;

const clean = (s: string | null | undefined) => (s ? s.replace(/\s+/g, " ").trim() : "");

/** KI-Antwort → RecipeDraft (wie aus dem Markdown-Import) */
export function extractToDraft(x: RecipeExtract, source: string | null): RecipeDraft {
  const ingredients = x.ingredients
    .filter((i) => clean(i.name))
    .map((i) => {
      const amount_text = clean(i.amount) || null;
      return { group_name: clean(i.group) || null, name: clean(i.name), amount_text, ...parseAmount(amount_text) };
    });
  const categories = x.categories.map(clean).filter(Boolean).slice(0, 4);
  const time_text = clean(x.time_text) || null;
  const nutrition_text = clean(x.nutrition_text);
  const derived = deriveDiet(categories, ingredients.map((i) => i.name));
  return {
    title: clean(x.title),
    subtitle: clean(x.subtitle) || null,
    source,
    cookbook: clean(x.cookbook_title) ? { title: clean(x.cookbook_title), page: x.cookbook_page ?? null } : null,
    categories,
    tags: [...new Set(categories.map(slugifyTag).filter(Boolean))],
    // Fleisch/Fisch aus den Zutaten hat Vorrang vor einer zu optimistischen KI-Einordnung
    diet: derived !== "vegetarisch" ? derived : x.diet,
    time_text,
    time_min: x.time_min && x.time_min > 0 ? x.time_min : parseTimeMinutes(time_text),
    servings: x.servings && x.servings > 0 ? x.servings : null,
    servings_text: clean(x.servings_text) || (x.servings ? String(x.servings) : null),
    ingredients,
    steps: x.steps.map(clean).filter(Boolean),
    tip: clean(x.tip) || null,
    nutrition: nutrition_text ? parseNutrition(nutrition_text) : null,
    extra_meta: { lines: [] },
  };
}
