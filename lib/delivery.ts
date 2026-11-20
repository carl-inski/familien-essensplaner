// Lieferdienste ohne Partner-Schnittstelle: Weder REWE noch Knuspr erlauben fremden Apps,
// den Warenkorb zu füllen (Stand 11/2026). Darum öffnet jeder offene Posten die Produktsuche
// des Shops mit einem sauberen Suchbegriff; in den Warenkorb legt man selbst.
// Gegenstück in Swift: ios/Packages/GnocchiCore/Sources/GnocchiCore/Delivery.swift

export type DeliveryShop = "rewe" | "knuspr";

export const DELIVERY_SHOPS: Record<DeliveryShop, { name: string; home: string; search: (q: string) => string }> = {
  rewe: {
    name: "REWE",
    home: "https://www.rewe.de/shop/",
    search: (q) => `https://www.rewe.de/shop/productList?search=${encodeURIComponent(q)}`,
  },
  knuspr: {
    name: "Knuspr",
    home: "https://www.knuspr.de/",
    search: (q) => `https://www.knuspr.de/suche?q=${encodeURIComponent(q)}`,
  },
};

const UNITS = [
  "kg", "g", "mg", "l", "ml", "cl", "dl", "el", "tl", "msp", "prise", "prisen", "stk", "stück", "st",
  "bund", "dose", "dosen", "packung", "packungen", "pck", "pkg", "päckchen", "becher", "glas", "gläser",
  "flasche", "flaschen", "beutel", "zehe", "zehen", "scheibe", "scheiben", "tasse", "tassen", "handvoll",
  "würfel", "stange", "stangen", "kopf", "köpfe", "netz", "schale", "schalen", "tube", "tuben",
];
const UNIT_RE = new RegExp(`^(?:${UNITS.join("|")})\\.?(?=\\s|$)`, "i");
const QUANTITY_RE = /^(?:ca\.?\s*|etwa\s+)?(?:\d+(?:[.,]\d+)?|\d+\/\d+|[½¼¾⅓⅔])(?:\s*(?:-|–|bis)\s*(?:\d+(?:[.,]\d+)?|[½¼¾]))?\s*(?:x\s+)?/i;
const ADJECTIVES = /^(?:groß|klein|mittelgroß|frisch|reif|getrocknet|gehackt)(?:e[mnrs]?)?\s+/i;

/**
 * Suchbegriff für die Shop-Suche aus einem Listenposten:
 * Menge, Einheit, Klammerzusätze und alles nach einem Komma fallen weg.
 * "480 g Hähnchenschenkel (ohne Knochen/Haut)" → "Hähnchenschenkel"
 */
export function shopSearchTerm(name: string): string {
  let s = name.normalize("NFC").replace(/\([^)]*\)/g, " ").replace(/\[[^\]]*\]/g, " ");
  s = s.split(/,(?!\d)|;/)[0];
  // Alternativen: nur die erste suchen ("Eisbergsalat oder Butterlatich" → "Eisbergsalat")
  s = s.split(/\s+oder\s+|\s+\/\s+/i)[0];
  s = s.replace(/\s+/g, " ").trim();
  for (let i = 0; i < 3; i++) {
    const before = s;
    s = s.replace(QUANTITY_RE, "").replace(UNIT_RE, "").replace(/^(?:x\s+|von\s+|à\s+)/i, "").trim();
    if (s === before) break;
  }
  s = s.replace(ADJECTIVES, "");
  s = s.replace(/\s+(?:nach Geschmack|zum Servieren|optional|n\. B\.|nach Belieben)$/i, "").trim();
  return s || name.trim();
}

export function shopSearchUrl(shop: DeliveryShop, name: string): string {
  return DELIVERY_SHOPS[shop].search(shopSearchTerm(name));
}
