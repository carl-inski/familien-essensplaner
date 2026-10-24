// Vorrat: Zutaten, die der Haushalt immer im Haus hat (Salz, Pfeffer …).
// Abgleich ohne KI über den Kern des Zutatennamens.

import { displayName } from "./quantity";

/** Schlüssel einer Zutat: „Pfeffer, frisch gemahlen“ → „pfeffer“, „Olivenöl (extra vergine)“ → „olivenöl“ */
export function pantryKey(name: string): string {
  return displayName(name)
    .toLowerCase()
    .replace(/\(.*?\)/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Zutaten einer Sammelzeile, je mit Alternativen:
 * „Muskat, Salz und Pfeffer“ → [[muskat], [salz], [pfeffer]],
 * „Kokosnussöl oder Olivenöl“ → [[kokosnussöl, olivenöl]].
 * Ein Komma trennt nur, wenn danach ein Nomen (großgeschriebenes Wort) folgt –
 * „Pfeffer, frisch gemahlen“ ist eine Zutat mit Zubereitungshinweis.
 */
export function pantryGroups(name: string): string[][] {
  const base = displayName(name).replace(/\(.*?\)/g, " ").replace(/\s+/g, " ").trim();
  const items: string[] = [];
  for (const chunk of base.split(/\s*,\s*/)) {
    // „frisch gemahlen“ ist ein Hinweis; „schwarzer Pfeffer“ (enthält ein Nomen) eine eigene Zutat
    if (items.length && !/(^|\s)\p{Lu}/u.test(chunk)) continue;
    items.push(...chunk.split(/\s+(?:und|&|\+)\s+/));
  }
  return items
    .map((it) => it.split(/\s+oder\s+|\s*\/\s*/).map((a) => a.trim().toLowerCase()).filter(Boolean))
    .filter((alts) => alts.length);
}

/** Alle Einzelzutaten einer Zeile (zum Eintragen in den Vorrat) */
export function pantryParts(name: string): string[] {
  return [...new Set(pantryGroups(name).flat())];
}

/** „schwarzer Pfeffer“ zählt als „pfeffer“ (letztes Wort), „Meersalz“ nicht als „salz“ */
function matchEntry(part: string, pantry: Set<string>): string | null {
  if (pantry.has(part)) return part;
  const last = part.split(" ").pop()!;
  return pantry.has(last) ? last : null;
}

/**
 * Was von einer Zutatenzeile nach Abzug des Vorrats übrig bleibt:
 * null = ganz im Vorrat, sonst der (ggf. gekürzte) Name.
 */
export function withoutPantry(name: string, pantry: Set<string>): string | null {
  if (!pantry.size) return name;
  const groups = pantryGroups(name);
  if (!groups.length) return name;
  const rest = groups.filter((alts) => !alts.some((a) => matchEntry(a, pantry)));
  if (!rest.length) return null;
  if (rest.length === groups.length) return name;
  // Teilweise im Vorrat: nur den Rest nennen, mit Großbuchstaben am Anfang
  const joined = rest.map((alts) => alts.join(" oder ")).join(", ");
  return joined.charAt(0).toUpperCase() + joined.slice(1);
}

/** Vorratseinträge, die eine Zutatenzeile abdecken (zum Wieder-Einkaufen) */
export function pantryEntriesFor(name: string, pantry: Set<string>): string[] {
  const out = new Set<string>();
  for (const alt of pantryGroups(name).flat()) {
    const hit = matchEntry(alt, pantry);
    if (hit) out.add(hit);
  }
  return [...out];
}
