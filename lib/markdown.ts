// Markdown-Import/-Export im Format von data/rezeptsammlung.md (Briefing Abschnitt 8)

import { parseAmount } from "./quantity";
import type { Diet } from "./types";

export interface MetaLine {
  key: string;
  value: string;
  /** 'head' = vor den Zutaten, 'tail' = nach der Zubereitung */
  where: "head" | "tail";
}

export interface DraftIngredient {
  group_name: string | null;
  name: string;
  amount: number | null;
  unit: string | null;
  amount_text: string | null;
}

export interface RecipeDraft {
  title: string;
  subtitle: string | null;
  source: string | null;
  cookbook: { title: string; page: number | null } | null;
  categories: string[];
  tags: string[];
  diet: Diet;
  time_text: string | null;
  time_min: number | null;
  servings: number | null;
  servings_text: string | null;
  ingredients: DraftIngredient[];
  steps: string[];
  tip: string | null;
  nutrition: { text: string; [k: string]: string } | null;
  extra_meta: { lines: MetaLine[] };
  /** Bild-URL aus einem Import (Webseite), sonst nicht gesetzt */
  image_url?: string | null;
}

const KNOWN_HEAD = ["Untertitel", "Quelle", "Kochbuch", "Kategorie", "Zeit", "Portionen", "Menge", "Tags"];
const KNOWN_TAIL = ["Tipp", "Nährwerte pro Portion"];

const MEAT_WORDS = ["hähnchen", "huhn", "hühner", "chicken", "schwein", "rind", "hack", "schinken", "speck", "bacon", "salami", "wurst", "lamm", "pute", "ente", "kalb", "geflügel", "fleisch"];
const FISH_WORDS = ["lachs", "garnele", "thunfisch", "fisch", "forelle", "kabeljau", "shrimp", "scampi", "dorade", "sardelle", "muschel"];

export function slugifyTag(s: string): string {
  return s
    .toLowerCase()
    .trim()
    .replace(/\s+/g, "-")
    .replace(/[^\p{L}\p{N}-]/gu, "");
}

/** GitHub-kompatibler Anker, wie im Inhaltsverzeichnis der Rezeptsammlung */
export function anchorFor(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^\p{L}\p{N} _-]/gu, "")
    .replace(/ /g, "-");
}

export function deriveDiet(categories: string[], ingredientNames: string[]): Diet {
  const cats = categories.map((c) => c.toLowerCase());
  if (cats.some((c) => c === "fisch")) return "fisch";
  if (cats.some((c) => ["geflügel", "rind", "schwein", "fleisch", "lamm", "wild"].includes(c))) return "fleisch";
  // Klammerzusätze und "gehackt" würden sonst als "hack" erkannt
  const names = ingredientNames.map((n) => n.toLowerCase().replace(/\(.*?\)/g, "").replace(/gehackt\p{L}*/gu, ""));
  if (names.some((n) => MEAT_WORDS.some((w) => n.includes(w)))) return "fleisch";
  if (names.some((n) => FISH_WORDS.some((w) => n.includes(w)))) return "fisch";
  return "vegetarisch";
}

/** Summiert Minuten-/Stundenangaben; Spannen zählen mit dem oberen Wert. */
export function parseTimeMinutes(text: string | null): number | null {
  if (!text) return null;
  let total = 0;
  let found = false;
  const re = /(\d+(?:[.,]\d+)?)(?:\s*[–-]\s*(\d+(?:[.,]\d+)?))?\s*(Min|Std|h\b)/gi;
  for (const m of text.matchAll(re)) {
    const v = Number((m[2] ?? m[1]).replace(",", "."));
    total += m[3].toLowerCase().startsWith("min") ? v : v * 60;
    found = true;
  }
  return found ? Math.round(total) : null;
}

function parseCookbook(value: string): { title: string; page: number | null } {
  const m = value.match(/^(.*?),\s*S\.\s*(\d+)\s*$/);
  if (m) return { title: m[1].trim(), page: Number(m[2]) };
  return { title: value.trim(), page: null };
}

export function parseNutrition(text: string): { text: string; [k: string]: string } {
  const out: { text: string; [k: string]: string } = { text };
  for (const part of text.split("|").map((p) => p.trim()).filter(Boolean)) {
    const kcal = part.match(/^([\d.,]+)\s*kcal$/i);
    if (kcal) {
      out.kcal = kcal[1];
      continue;
    }
    const kv = part.match(/^(.+?)\s+([\d.,]+\s*\S*)$/);
    if (kv) out[kv[1]] = kv[2];
  }
  return out;
}

function splitRow(line: string): string[] {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((c) => c.trim());
}

function parseRecipeBlock(block: string): RecipeDraft | null {
  const lines = block.split("\n");
  const titleLine = lines.find((l) => /^##\s+/.test(l));
  if (!titleLine) return null;
  const title = titleLine.replace(/^##\s+/, "").trim();

  const meta: MetaLine[] = [];
  const ingredients: DraftIngredient[] = [];
  const steps: string[] = [];
  let section: "head" | "zutaten" | "zubereitung" | "tail" = "head";
  let group: string | null = null;

  for (const raw of lines) {
    const line = raw.replace(/\s+$/, "");
    if (/^##\s+/.test(line)) continue;
    if (/^###\s+Zutaten/i.test(line)) { section = "zutaten"; continue; }
    if (/^###\s+Zubereitung/i.test(line)) { section = "zubereitung"; continue; }

    const metaMatch = line.match(/^\*\*(.+?):\*\*\s*(.*)$/);
    if (metaMatch && section !== "zutaten") {
      const where = section === "head" ? "head" : "tail";
      if (section === "zubereitung") section = "tail";
      meta.push({ key: metaMatch[1].trim(), value: metaMatch[2].trim(), where });
      continue;
    }

    if (section === "zutaten" && line.startsWith("|")) {
      const cells = splitRow(line);
      if (cells.length < 2) continue;
      const [name, amountText] = cells;
      if (/^-+$/.test(name.replace(/:/g, "")) || (name === "Zutat" && amountText === "Menge")) continue;
      const bold = name.match(/^\*\*(.+)\*\*$/);
      if (bold && !amountText) {
        group = bold[1].trim();
        continue;
      }
      const parsed = parseAmount(amountText);
      ingredients.push({
        group_name: group,
        name,
        amount: parsed.amount,
        unit: parsed.unit,
        amount_text: amountText || null,
      });
      continue;
    }

    if (section === "zubereitung") {
      const step = line.match(/^\d+\.\s+(.*)$/);
      if (step) steps.push(step[1].trim());
    }
  }

  const get = (key: string) => meta.find((m) => m.key === key)?.value ?? null;
  const categories = (get("Kategorie") ?? "")
    .split(" / ")
    .map((c) => c.trim())
    .filter(Boolean);
  const tagsLine = get("Tags");
  const tags = tagsLine
    ? tagsLine.split(",").map((t) => slugifyTag(t)).filter(Boolean)
    : categories.map(slugifyTag);

  const portionen = get("Portionen");
  const menge = get("Menge");
  const servingsMatch = portionen?.match(/\d+/);
  const kochbuch = get("Kochbuch");
  const naehrwerte = get("Nährwerte pro Portion");
  const timeText = get("Zeit");

  const extra = meta.filter((m) => !(m.where === "head" ? KNOWN_HEAD : KNOWN_TAIL).includes(m.key));

  return {
    title,
    subtitle: get("Untertitel"),
    source: get("Quelle"),
    cookbook: kochbuch ? parseCookbook(kochbuch) : null,
    categories,
    tags,
    diet: deriveDiet(categories, ingredients.map((i) => i.name)),
    time_text: timeText,
    time_min: parseTimeMinutes(timeText),
    servings: servingsMatch ? Number(servingsMatch[0]) : null,
    servings_text: portionen ?? menge,
    ingredients,
    steps,
    tip: get("Tipp"),
    nutrition: naehrwerte ? parseNutrition(naehrwerte) : null,
    extra_meta: { lines: extra },
  };
}

/** Parst eine komplette Rezeptsammlung (oder ein einzelnes Rezept). */
export function parseRecipeCollection(markdown: string): RecipeDraft[] {
  const text = markdown.replace(/\r\n/g, "\n");
  const blocks = text.split(/\n-{3,}\s*\n/);
  const recipes: RecipeDraft[] = [];
  for (const block of blocks) {
    const h2 = block.match(/^##\s+(.+)$/m);
    if (!h2) continue;
    if (h2[1].trim() === "Inhalt" && !/###\s+Zutaten/.test(block)) continue;
    const r = parseRecipeBlock(block);
    if (r) recipes.push(r);
  }
  return recipes;
}

function metaLine(key: string, value: string): string {
  return `**${key}:** ${value}  `;
}

export function recipeToMarkdown(r: RecipeDraft): string {
  const out: string[] = [`## ${r.title}`, ""];
  const head: string[] = [];
  if (r.subtitle) head.push(metaLine("Untertitel", r.subtitle));
  if (r.source) head.push(metaLine("Quelle", r.source));
  if (r.cookbook) head.push(metaLine("Kochbuch", r.cookbook.page ? `${r.cookbook.title}, S. ${r.cookbook.page}` : r.cookbook.title));
  if (r.categories.length) head.push(metaLine("Kategorie", r.categories.join(" / ")));
  const derivedTags = r.categories.map(slugifyTag);
  if (r.tags.join(",") !== derivedTags.join(",")) head.push(metaLine("Tags", r.tags.join(", ")));
  if (r.time_text) head.push(metaLine("Zeit", r.time_text));
  if (r.servings !== null) head.push(metaLine("Portionen", r.servings_text ?? String(r.servings)));
  else if (r.servings_text) head.push(metaLine("Menge", r.servings_text));
  for (const m of r.extra_meta.lines.filter((l) => l.where === "head")) head.push(metaLine(m.key, m.value));
  out.push(...head, "");

  out.push("### Zutaten", "", "| Zutat | Menge |", "|---|---|");
  let group: string | null = null;
  for (const i of r.ingredients) {
    if (i.group_name && i.group_name !== group) out.push(`| **${i.group_name}** | |`);
    group = i.group_name;
    out.push(`| ${i.name} | ${i.amount_text ?? ""} |`);
  }
  out.push("", "### Zubereitung", "");
  r.steps.forEach((s, idx) => out.push(`${idx + 1}. ${s}`));

  const tail: string[] = [];
  if (r.tip) tail.push(metaLine("Tipp", r.tip));
  if (r.nutrition?.text) tail.push(metaLine("Nährwerte pro Portion", r.nutrition.text));
  for (const m of r.extra_meta.lines.filter((l) => l.where === "tail")) tail.push(metaLine(m.key, m.value));
  for (const t of tail) out.push("", t.trimEnd());
  return out.join("\n");
}

export function collectionToMarkdown(recipes: RecipeDraft[]): string {
  const toc = recipes.map((r, i) => `${i + 1}. [${r.title}](#${anchorFor(r.title)})`);
  const parts = ["# Rezeptsammlung", "", "## Inhalt", "", ...toc, "", "---", ""];
  const body = recipes.map((r) => recipeToMarkdown(r)).join("\n\n---\n\n");
  return parts.join("\n") + "\n" + body + "\n";
}
