// Vorrat: Zutaten, die der Haushalt immer im Haus hat (Salz, Pfeffer …).
// Abgleich ohne KI über den Kern des Zutatennamens.
//
// Regeln:
// - Was man mit dem Häuschen markiert, wird als ganze Zutat gemerkt
//   („Hähnchenober- und -unterschenkel“). Nur echte Sammelzeilen wie
//   „Salz, Pfeffer“ oder „Salz und Pfeffer“ werden in Einzelzutaten zerlegt.
// - Wörter mit Ergänzungsstrich („Rinder- oder Gemüsebrühe“) werden nie getrennt.
// - „oder“ sind Alternativen: Ist eine davon im Vorrat, ist die Zeile gedeckt.
// - Einzahl/Mehrzahl gelten als gleich („Zwiebel“ = „Zwiebeln“), ebenso eine
//   Beschreibung davor („schwarzer Pfeffer“ = „Pfeffer“). „Meersalz“ ist aber nicht „Salz“.

import { displayName } from "./quantity";

/** Schlüssel einer Zutat: „Pfeffer, frisch gemahlen“ → „pfeffer“, „Olivenöl (extra vergine)“ → „olivenöl“ */
export function pantryKey(name: string): string {
  return groupsOf(name)
    .map((alts) => alts.join(" oder "))
    .join(", ");
}

/** Grober Wortstamm für Einzahl/Mehrzahl: „zwiebeln“ → „zwiebel“, „tomaten“ → „tomat“, „eier“ → „ei“ */
function stem(word: string): string {
  return word.replace(/(ern|er|en|n|e|s)$/u, "") || word;
}
const same = (a: string, b: string) => a === b || stem(a) === stem(b);

/**
 * Trennt an Bindewörtern, aber nur zwischen ganzen Wörtern – nicht bei
 * „Hähnchenober- und -unterschenkel“. `separator` braucht eine Klammergruppe.
 */
function splitWords(text: string, separator: RegExp): string[] {
  const parts = text.split(separator); // [wort, trenner, wort, trenner, …]
  const out: string[] = [];
  let current = parts[0];
  for (let i = 1; i < parts.length; i += 2) {
    const sep = parts[i];
    const next = parts[i + 1] ?? "";
    if (/-$/.test(current) || /^-/.test(next)) current = `${current}${sep}${next}`;
    else {
      out.push(current);
      current = next;
    }
  }
  out.push(current);
  return out.map((w) => w.trim()).filter(Boolean);
}

/**
 * Zutaten einer Zeile, je mit Alternativen (alles klein, ohne Klammerzusätze):
 * „Muskat, Salz und Pfeffer“ → [[muskat], [salz], [pfeffer]],
 * „Kokosnussöl oder Olivenöl“ → [[kokosnussöl, olivenöl]],
 * „Hähnchenober- und -unterschenkel (mit Haut)“ → [[hähnchenober- und -unterschenkel]].
 * Ein Komma trennt nur, wenn danach ein Nomen (großgeschriebenes Wort) folgt –
 * „Pfeffer, frisch gemahlen“ ist eine Zutat mit Zubereitungshinweis.
 */
function groupsOf(name: string): string[][] {
  const base = displayName(name).replace(/\(.*?\)/g, " ").replace(/\s+/g, " ").trim();
  const items: string[] = [];
  for (const chunk of base.split(/\s*,\s*/)) {
    if (!chunk) continue;
    if (items.length && !/(^|\s)\p{Lu}/u.test(chunk)) continue;
    items.push(...splitWords(chunk, /(\s+(?:und|&|\+)\s+)/));
  }
  return items
    .map((it) =>
      splitWords(it, /(\s+oder\s+)/)
        .flatMap((a) => (/[^\s]\/[^\s]/.test(a) ? [a] : a.split(/\s*\/\s*/)))
        .map((a) => a.trim().toLowerCase())
        .filter(Boolean),
    )
    .filter((alts) => alts.length);
}

/** Ist eine einzelne Zutat (bzw. Alternative) durch einen Vorratseintrag gedeckt? */
function entryFor(alt: string, pantry: Set<string>): string | null {
  for (const entry of pantry) {
    if (!isValidEntry(entry)) continue;
    if (same(alt, entry)) return entry;
    // „schwarzer pfeffer“ ↔ „pfeffer“: letztes Wort gleich, Eintrag ist ein einzelnes Wort
    if (!entry.includes(" ") && same(alt.split(" ").pop()!, entry)) return entry;
  }
  return null;
}

/** Vorratseinträge, die eine Zeile abdecken – Ganzes zuerst, dann Teile */
export function pantryEntriesFor(name: string, pantry: Set<string>): string[] {
  const out = new Set<string>();
  const whole = pantryKey(name);
  if (pantry.has(whole)) out.add(whole);
  for (const alts of groupsOf(name)) {
    const key = alts.join(" oder ");
    if (pantry.has(key)) out.add(key);
    for (const alt of alts) {
      const hit = entryFor(alt, pantry);
      if (hit) out.add(hit);
    }
  }
  return [...out];
}

/**
 * Was von einer Zutatenzeile nach Abzug des Vorrats übrig bleibt:
 * null = ganz im Vorrat, sonst der (ggf. gekürzte) Name.
 */
export function withoutPantry(name: string, pantry: Set<string>): string | null {
  if (!pantry.size) return name;
  if (pantry.has(pantryKey(name))) return null;
  const groups = groupsOf(name);
  if (!groups.length) return name;
  const covered = (alts: string[]) => pantry.has(alts.join(" oder ")) || alts.some((a) => entryFor(a, pantry));
  const rest = groups.filter((alts) => !covered(alts));
  if (!rest.length) return null;
  if (rest.length === groups.length) return name;
  // Teilweise im Vorrat: nur den Rest nennen, mit Großbuchstaben am Anfang
  const joined = rest.map((alts) => alts.join(" oder ")).join(", ");
  return joined.charAt(0).toUpperCase() + joined.slice(1);
}

/**
 * Einträge, die beim Tippen aufs Häuschen gemerkt werden:
 * Sammelzeilen („Salz, Pfeffer“) als einzelne Zutaten, alles andere als Ganzes.
 */
export function pantryEntriesToAdd(name: string): string[] {
  const groups = groupsOf(name);
  if (groups.length <= 1) return [pantryKey(name)].filter(Boolean);
  return [...new Set(groups.map((alts) => alts.join(" oder ")))];
}

/** Freitext im Haushalt („Olivenöl, Zucker“): jede durch Komma getrennte Angabe einzeln */
export function pantryEntriesFromInput(text: string): string[] {
  return [...new Set(text.split(/\s*[,;\n]\s*/).map((t) => pantryKey(t)).filter(Boolean))];
}

/** Bruchstücke wie „-unterschenkel“ (aus einer älteren Version) zählen nicht */
export function isValidEntry(entry: string): boolean {
  return !/^-|-$/.test(entry) && entry.trim().length > 0;
}

/** Anzeigename eines Eintrags: erster Buchstabe groß */
export function pantryLabel(entry: string): string {
  return entry.charAt(0).toUpperCase() + entry.slice(1);
}
