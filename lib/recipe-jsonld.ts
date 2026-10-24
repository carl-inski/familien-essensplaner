// Liest schema.org/Recipe aus dem JSON-LD einer Webseite – ohne KI.
// Die meisten Rezeptseiten (Chefkoch, Lecker, Blogs mit WP Recipe Maker …) liefern es mit.

import { deriveDiet, parseNutrition, slugifyTag, type RecipeDraft } from "./markdown";
import { parseAmount, splitIngredientLine } from "./quantity";

type Json = unknown;
type Obj = Record<string, Json>;

const isObj = (v: Json): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
const arr = (v: Json): Json[] => (Array.isArray(v) ? v : v === undefined || v === null ? [] : [v]);

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", auml: "ä", ouml: "ö", uuml: "ü", Auml: "Ä", Ouml: "Ö", Uuml: "Ü", szlig: "ß", frac12: "½", frac14: "¼", frac34: "¾", ndash: "–", hellip: "…" };

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+\d*);/gi, (m, e: string) => {
    if (e[0] === "#") {
      const code = e[1].toLowerCase() === "x" ? Number.parseInt(e.slice(2), 16) : Number(e.slice(1));
      return Number.isFinite(code) ? String.fromCodePoint(code) : m;
    }
    return ENTITIES[e] ?? m;
  });
}

/** Text ohne HTML-Tags, Entities aufgelöst, Leerraum zusammengefasst */
export function cleanText(v: Json): string {
  if (typeof v !== "string" && typeof v !== "number") return "";
  return decodeEntities(String(v).replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, " "))
    .replace(/[ \t ]+/g, " ")
    .replace(/\s*\n\s*/g, "\n")
    .trim();
}

function hasType(o: Obj, type: string): boolean {
  return arr(o["@type"]).some((t) => typeof t === "string" && t.toLowerCase() === type.toLowerCase());
}

function findRecipe(node: Json, depth = 0): Obj | null {
  if (depth > 6) return null;
  for (const n of arr(node)) {
    if (!isObj(n)) continue;
    if (hasType(n, "Recipe")) return n;
    for (const key of ["@graph", "mainEntity", "itemListElement", "item"]) {
      const hit = n[key] !== undefined ? findRecipe(n[key], depth + 1) : null;
      if (hit) return hit;
    }
  }
  return null;
}

/** ISO-8601-Dauer wie PT1H15M → Minuten */
export function isoDurationMinutes(v: Json): number | null {
  if (typeof v !== "string") return null;
  const m = v.match(/^P(?:(\d+)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:\d+(?:\.\d+)?S)?)?$/i);
  if (!m || (!m[1] && !m[2] && !m[3])) return null;
  const total = Number(m[1] ?? 0) * 1440 + Number(m[2] ?? 0) * 60 + Number(m[3] ?? 0);
  return total > 0 ? Math.round(total) : null;
}

function steps(v: Json, depth = 0): string[] {
  if (depth > 4) return [];
  if (typeof v === "string") {
    const text = cleanText(v);
    // Ein einzelner Textblock: an Zeilen bzw. Nummerierung aufteilen
    return text
      .split(/\n+|(?:^|\s)(?=\d+\.\s)/)
      .map((s) => s.replace(/^\d+\.\s*/, "").trim())
      .filter(Boolean);
  }
  const out: string[] = [];
  for (const s of arr(v)) {
    if (typeof s === "string") out.push(...steps(s, depth + 1));
    else if (isObj(s)) {
      if (s.itemListElement !== undefined) out.push(...steps(s.itemListElement, depth + 1));
      else {
        const text = cleanText(s.text ?? s.name ?? s.description);
        if (text) out.push(text.replace(/\n+/g, " "));
      }
    }
  }
  return out;
}

function imageUrl(v: Json): string | null {
  for (const i of arr(v)) {
    const url = typeof i === "string" ? i : isObj(i) ? i.url ?? i.contentUrl : null;
    if (typeof url === "string" && /^https:\/\//.test(url)) return url;
  }
  return null;
}

function list(v: Json): string[] {
  return arr(v)
    .flatMap((x) => (typeof x === "string" ? x.split(",") : []))
    .map((x) => cleanText(x))
    .filter(Boolean);
}

const NUTRITION_LABELS: [string, string, string][] = [
  ["calories", "", "kcal"],
  ["proteinContent", "Eiweiß", "g"],
  ["fatContent", "Fett", "g"],
  ["carbohydrateContent", "Kohlenhydrate", "g"],
  ["fiberContent", "Ballaststoffe", "g"],
];

function nutrition(v: Json): RecipeDraft["nutrition"] {
  if (!isObj(v)) return null;
  const parts: string[] = [];
  for (const [key, label, unit] of NUTRITION_LABELS) {
    const raw = cleanText(v[key]);
    const n = raw.match(/[\d.,]+/)?.[0];
    if (!n) continue;
    const value = n.replace(".", ",");
    parts.push(label ? `${label} ${value} ${unit}` : `${value} ${unit}`);
  }
  return parts.length ? parseNutrition(parts.join(" | ")) : null;
}

/** Rezept aus einem bereits geparsten JSON-LD-Knoten */
export function recipeFromJsonLd(node: Json, sourceUrl: string | null): RecipeDraft | null {
  const r = findRecipe(node);
  if (!r) return null;
  const title = cleanText(r.name);
  const ingredients = arr(r.recipeIngredient ?? r.ingredients)
    .map((l) => cleanText(l))
    .filter(Boolean)
    .map((line) => {
      const { amount_text, name } = splitIngredientLine(line);
      return { group_name: null, name, amount_text, ...parseAmount(amount_text) };
    });
  if (!title || (!ingredients.length && !r.recipeInstructions)) return null;

  const prep = isoDurationMinutes(r.prepTime);
  const cook = isoDurationMinutes(r.cookTime);
  const total = isoDurationMinutes(r.totalTime) ?? (prep || cook ? (prep ?? 0) + (cook ?? 0) : null);
  const time_text = prep && cook ? `Vorbereitung ${prep} Min. / Garzeit ${cook} Min.` : total ? `${total} Min.` : null;

  const yieldText = arr(r.recipeYield).map((y) => cleanText(y)).find(Boolean) ?? null;
  const servingsNum = yieldText ? Number(yieldText.match(/\d+/)?.[0]) : NaN;
  const categories = [...new Set([...list(r.recipeCategory), ...list(r.recipeCuisine)])].slice(0, 4);
  const description = cleanText(r.description);

  return {
    title,
    subtitle: description && description.length <= 140 ? description : null,
    source: sourceUrl,
    cookbook: null,
    categories,
    tags: [...new Set([...categories, ...list(r.keywords)].map(slugifyTag).filter(Boolean))].slice(0, 8),
    diet: deriveDiet(categories, ingredients.map((i) => i.name)),
    time_text,
    time_min: total,
    servings: Number.isFinite(servingsNum) && servingsNum > 0 ? servingsNum : null,
    servings_text: yieldText,
    ingredients,
    steps: steps(r.recipeInstructions),
    tip: null,
    nutrition: nutrition(r.nutrition),
    extra_meta: { lines: [] },
    image_url: imageUrl(r.image),
  };
}

/** Sucht alle JSON-LD-Blöcke einer HTML-Seite nach einem Rezept ab */
export function recipeFromHtml(html: string, sourceUrl: string | null): RecipeDraft | null {
  const re = /<script[^>]*type=["']?application\/ld\+json["']?[^>]*>([\s\S]*?)<\/script>/gi;
  for (const m of html.matchAll(re)) {
    let data: Json;
    try {
      data = JSON.parse(m[1].trim());
    } catch {
      continue;
    }
    const draft = recipeFromJsonLd(data, sourceUrl);
    if (draft) return draft;
  }
  return null;
}

/** Lesbarer Seitentext für die KI, falls kein JSON-LD da ist */
export function pageText(html: string, maxChars = 24000): string {
  const body = html
    .replace(/<(script|style|noscript|svg|nav|footer|header|form|iframe)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<\/(p|div|li|h\d|tr|section|article)>/gi, "\n");
  return cleanText(body).replace(/\n{2,}/g, "\n").slice(0, maxChars);
}

/** Sprache der Seite aus <html lang> */
export function pageLanguage(html: string): string | null {
  return html.match(/<html[^>]*\slang=["']?([a-zA-Z-]+)/i)?.[1].toLowerCase() ?? null;
}

const FOREIGN_UNITS = /\b(?:tbsp|tsp|cups?|oz|ounces?|lbs?|pounds?|pints?|tablespoons?|teaspoons?|cloves?|pinch)\b/i;

/** Ist ein JSON-LD-Rezept nicht deutsch bzw. nicht metrisch? Dann übersetzt die KI. */
export function needsTranslation(d: RecipeDraft, lang: string | null): boolean {
  if (lang?.startsWith("de")) return false;
  if (lang) return true;
  return d.ingredients.some((i) => FOREIGN_UNITS.test(`${i.amount_text ?? ""} ${i.name}`));
}
