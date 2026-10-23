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
};

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
  if (original.amount === amount && original.unit === unit) return amountText;
  const formatted = formatAmount(amount, unit);
  const rest = amountText.replace(/^[\d.,/½¼¾⅓⅔⅛]+(\s*[–-]\s*[\d.,/½¼¾⅓⅔⅛]+)?\s*/, "");
  if (!unit) return `${formatted} ${rest}`.trim();
  const afterUnit = rest.replace(/^[A-Za-zÄÖÜäöüß.]+\s*/, "");
  return `${formatted} ${afterUnit}`.trim();
}
