// Mengen-Parsing, Skalierung und Formatierung (Briefing Abschnitt 7)

const FRACTIONS: Record<string, number> = { "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1 / 3, "⅔": 2 / 3, "⅛": 0.125 };

// Kanonische Einheit je Schreibweise
const UNIT_ALIASES: Record<string, string> = {
  g: "g", gramm: "g",
  kg: "kg",
  ml: "ml",
  l: "l", liter: "l",
  el: "EL", tl: "TL",
  stück: "Stück", stk: "Stück", "stk.": "Stück",
  bund: "Bund",
  dose: "Dose", dosen: "Dose",
  "pck.": "Pck.", pck: "Pck.", packung: "Pck.", packungen: "Pck.", päckchen: "Pck.",
  zehe: "Zehen", zehen: "Zehen",
  kugel: "Kugeln", kugeln: "Kugeln",
  kopf: "Kopf",
  handvoll: "Handvoll",
  scheibe: "Scheiben", scheiben: "Scheiben",
  prise: "Prise", prisen: "Prise",
  schuss: "Schuss",
  cm: "cm",
  becher: "Becher",
  glas: "Glas",
  tasse: "Tasse", tassen: "Tasse",
  "esslöffel": "EL", "essl.": "EL", "teelöffel": "TL", "teel.": "TL",
  msp: "Msp.", "msp.": "Msp.", messerspitze: "Msp.",
  // Englische Angaben – werden beim Einlesen metrisch umgerechnet (siehe IMPERIAL)
  tbsp: "EL", tbs: "EL", tablespoon: "EL", tablespoons: "EL",
  tsp: "TL", teaspoon: "TL", teaspoons: "TL",
  cup: "cup", cups: "cup",
  oz: "oz", ounce: "oz", ounces: "oz",
  lb: "lb", lbs: "lb", pound: "lb", pounds: "lb",
  pint: "pint", pints: "pint",
  quart: "quart", quarts: "quart",
};

/** Feste Umrechnung angloamerikanischer Einheiten (US-Maße) */
const IMPERIAL: Record<string, { factor: number; unit: string }> = {
  cup: { factor: 240, unit: "ml" },
  oz: { factor: 28.35, unit: "g" },
  lb: { factor: 453.6, unit: "g" },
  pint: { factor: 473, unit: "ml" },
  quart: { factor: 946, unit: "ml" },
};

/** Krumme Umrechnungsergebnisse auf alltagstaugliche Werte runden (5er unter 100, sonst 10er) */
function metricRound(v: number): number {
  return v < 100 ? Math.max(5, Math.round(v / 5) * 5) : Math.round(v / 10) * 10;
}

export function isImperialUnit(word: string | null | undefined): boolean {
  const u = word ? UNIT_ALIASES[word.toLowerCase()] : undefined;
  return !!u && u in IMPERIAL;
}

const PIECE_UNITS = new Set([null, "Stück", "Kugeln", "Zehen", "Dose", "Pck.", "Bund", "Kopf", "Glas", "Becher", "Scheiben"]);

export interface ParsedAmount {
  amount: number | null;
  unit: string | null;
}

function parseNumber(token: string): number | null {
  const t = token.trim();
  if (!t) return null;
  if (t in FRACTIONS) return FRACTIONS[t];
  // "1½"
  const mixed = t.match(/^(\d+)([½¼¾⅓⅔⅛])$/);
  if (mixed) return Number(mixed[1]) + FRACTIONS[mixed[2]];
  const frac = t.match(/^(\d+)\/(\d+)$/);
  if (frac) return Number(frac[1]) / Number(frac[2]);
  const n = Number(t.replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

/**
 * Liest Menge und Einheit aus einem Freitext wie "1,5 EL", "2–3 EL", "7g", "½ Kopf",
 * "2 Kugeln (à 125 g)". Spannen nehmen den oberen Wert. Nicht parsebar → amount = null.
 */
export function parseAmount(text: string | null | undefined): ParsedAmount {
  if (!text) return { amount: null, unit: null };
  const s = text.trim();
  const num = "(\\d+(?:[.,]\\d+)?[½¼¾⅓⅔⅛]?|\\d+\\/\\d+|[½¼¾⅓⅔⅛])";
  const re = new RegExp(`^${num}(?:\\s*[–-]\\s*${num})?\\s*([A-Za-zÄÖÜäöüß.]+)?`);
  const m = s.match(re);
  if (!m) return { amount: null, unit: null };
  const amount = parseNumber(m[2] ?? m[1]);
  if (amount === null) return { amount: null, unit: null };
  const rawUnit = m[3]?.toLowerCase();
  const unit = rawUnit ? UNIT_ALIASES[rawUnit] ?? null : null;
  const imp = unit ? IMPERIAL[unit] : undefined;
  if (imp) return { amount: metricRound(amount * imp.factor), unit: imp.unit };
  return { amount, unit };
}

function roundTo(value: number, step: number): number {
  return Math.round(value / step) * step;
}

/** Skaliert eine Menge und rundet nach den Regeln aus Abschnitt 7. Gibt Basiseinheit g/ml zurück. */
export function scaleAmount(amount: number, unit: string | null, factor: number): { amount: number; unit: string | null } {
  let value = amount * factor;
  let u = unit;
  if (u === "kg") { value *= 1000; u = "g"; }
  if (u === "l") { value *= 1000; u = "ml"; }

  if (u === "g" || u === "ml") {
    value = value < 100 ? roundTo(value, 5) : roundTo(value, 10);
    if (value === 0 && amount > 0) value = 5;
  } else if (u === "EL" || u === "TL") {
    value = Math.max(0.5, roundTo(value, 0.5));
  } else if (PIECE_UNITS.has(u)) {
    // Stückzutaten aufrunden; Bruchteile unter 1 (z. B. ½ Kopf) auf halbe Stück
    value = value < 1 ? Math.ceil(value * 2 - 1e-9) / 2 : Math.ceil(value - 1e-9);
  } else {
    value = Math.max(0.5, roundTo(value, 0.5));
  }
  return { amount: Number(value.toFixed(3)), unit: u };
}

export function formatNumber(n: number): string {
  // Dezimalkomma statt ½ – Bring! und Erinnerungen lesen das zuverlässiger
  return n.toLocaleString("de-DE", { maximumFractionDigits: 2 });
}

/** "750 g", "1,25 kg", "3", "1,5 EL" */
export function formatAmount(amount: number | null, unit: string | null): string {
  if (amount === null) return "";
  if (unit === "g" && amount >= 1000) return `${formatNumber(amount / 1000)} kg`;
  if (unit === "ml" && amount >= 1000) return `${formatNumber(amount / 1000)} l`;
  return unit ? `${formatNumber(amount)} ${unit}` : formatNumber(amount);
}

/**
 * Normalisierter Name für die Wochen-Aggregation. Klammerzusätze bleiben erhalten
 * ("Spinat (TK)" ≠ "Spinat (frisch)"), nur reine Hinweise wie "(optional)" fallen weg.
 */
export function normalizeName(name: string): string {
  return displayName(name).replace(/\s+/g, " ").trim().toLowerCase();
}

/** Anzeigename ohne Hinweis-Klammern wie "(optional)" oder "(zum Würzen)" */
export function displayName(name: string): string {
  const cleaned = name
    .replace(/\s*\((?:optional|zum |für |als |nach )[^)]*\)/gi, "")
    .replace(/\s+/g, " ")
    .trim();
  return cleaned || name;
}

/** Mengenspalte nach Skalierung; behält Zusätze wie "mittelgroße" oder "(à 125 g)" bei */
export function scaledAmountText(amountText: string | null, amount: number | null, unit: string | null, original: { amount: number | null; unit: string | null }): string {
  if (amount === null || !amountText) return amountText ?? "";
  // „1 cup“ steht im Text, gespeichert sind 240 ml → immer metrisch anzeigen
  const textUnit = amountText.replace(/^[\d.,/½¼¾⅓⅔⅛]+(\s*[–-]\s*[\d.,/½¼¾⅓⅔⅛]+)?\s*/, "").match(/^[A-Za-zÄÖÜäöüß.]+/)?.[0];
  if (isImperialUnit(textUnit)) {
    const after = amountText.replace(/^[\d.,/½¼¾⅓⅔⅛]+(\s*[–-]\s*[\d.,/½¼¾⅓⅔⅛]+)?\s*[A-Za-zÄÖÜäöüß.]+\s*/, "");
    return `${formatAmount(amount, unit)} ${after}`.trim();
  }
  if (original.amount === amount && original.unit === unit) return amountText;
  const formatted = formatAmount(amount, unit);
  const rest = amountText.replace(/^[\d.,/½¼¾⅓⅔⅛]+(\s*[–-]\s*[\d.,/½¼¾⅓⅔⅛]+)?\s*/, "");
  if (!unit) return `${formatted} ${rest}`.trim();
  const afterUnit = rest.replace(/^[A-Za-zÄÖÜäöüß.]+\s*/, "");
  return `${formatted} ${afterUnit}`.trim();
}

const NUM = "(?:\\d+(?:[.,]\\d+)?[½¼¾⅓⅔⅛]?|\\d+\\/\\d+|[½¼¾⅓⅔⅛])";
const LINE_RE = new RegExp(`^(${NUM}(?:\\s*[–-]\\s*${NUM})?)\\s*(?:([A-Za-zÄÖÜäöüß]+\\.?)(?=\\s|$))?\\s*(.*)$`);

/**
 * Trennt eine Zutatenzeile („200 g Mehl“, „2 große Zwiebeln“, „1 Prise Salz“)
 * in Mengentext und Name. Ohne erkennbare Menge bleibt alles im Namen.
 */
export function splitIngredientLine(line: string): { amount_text: string | null; name: string } {
  const s = line.replace(/\s+/g, " ").replace(/^(?:ca\.|etwa|circa)\s*/i, "").trim();
  const m = s.match(LINE_RE);
  if (!m) return { amount_text: null, name: s };
  const [, num, word, rest] = m;
  if (word && UNIT_ALIASES[word.toLowerCase()]) {
    return { amount_text: `${num} ${word}`, name: rest.replace(/^[,:]\s*/, "").trim() || s };
  }
  const name = `${word ?? ""} ${rest}`.trim();
  return name ? { amount_text: num, name } : { amount_text: null, name: s };
}
