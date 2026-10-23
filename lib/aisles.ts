// Supermarkt-Bereiche per Schlagwort-Tabelle (MVP, Briefing 4.8)
// Reihenfolge zählt: die erste passende Regel gewinnt, spezifische Begriffe stehen deshalb oben.

export const AISLES = ["Obst & Gemüse", "Kühlregal", "Frischetheke", "Trockenware", "Gewürze", "Tiefkühl", "Getränke", "Sonstiges"] as const;
export type Aisle = (typeof AISLES)[number];

const RULES: [Aisle, string[]][] = [
  ["Tiefkühl", ["(tk", "tk-", "tk ", "tiefkühl"]],
  ["Trockenware", ["kokosmilch", "passierte", "tomatenmark", "(dose", "dose)", ", dose", "brühe", "öl", "essig", "sojasauce", "mirin", "hot sauce", "süß-sauer", "milchreis", "reispapier", "erdnussbutter", "marmelade", "honig", "sirup", "schoko", "pistazie", "haselnuss", "cashew", "kerne", "kapern", "oliven"]],
  ["Gewürze", ["salz", "pfeffer", "pulver", "zimt", "kreuzkümmel", "muskat", "getrocknet", "dill", "sesam", "currypaste", "misopaste", "chili", "thymian", "räucherpaprika"]],
  ["Frischetheke", ["hähnchen", "huhn", "schwein", "rinderhack", "hack", "schinken", "lachs", "garnele", "fisch", "speck", "geschnetzeltes", "filet"]],
  ["Kühlregal", ["feta", "käse", "mozzarella", "parmesan", "cheddar", "schmand", "sahne", "milch", "joghurt", "butter", "frischkäse", "crème", "creme", "eier", "ei", "mürbeteig", "gnocchi", "lasagneblätter", "quark", "guacamole", "tortilla"]],
  ["Obst & Gemüse", ["zwiebel", "knoblauch", "ingwer", "tomate", "spinat", "rucola", "salat", "latich", "gurke", "karotte", "möhre", "paprika", "zitrone", "limette", "orange", "banane", "ananas", "avocado", "petersilie", "koriander", "minze", "basilikum", "schnittlauch", "oregano", "champignon", "pilz", "spargel", "kartoffel", "sprossen", "lauch", "zucchini", "aubergine", "beeren", "apfel"]],
  ["Trockenware", ["nudel", "pasta", "penne", "farfalle", "reis", "mehl", "hefe", "zucker", "kichererbsen", "bohnen", "mais", "senf", "brot", "chips", "balsamico"]],
  ["Getränke", ["wein", "sake", "sherry"]],
];

export function aisleFor(name: string): Aisle {
  const full = name.toLowerCase();
  // Klammerzusätze wie "(fein gehackt)" verfälschen sonst die Zuordnung –
  // nur Muster, die selbst eine Klammer bzw. "tk" enthalten, prüfen den vollen Namen
  const bare = full.replace(/\(.*?\)/g, " ");
  for (const [aisle, words] of RULES) {
    const hit = words.some((w) => {
      const n = /[()]|tk/.test(w) ? full : bare;
      return w.length <= 2 ? new RegExp(`(^|[^\\p{L}])${w}([^\\p{L}]|$)`, "u").test(n) : n.includes(w);
    });
    if (hit) return aisle;
  }
  return "Sonstiges";
}

/** Leitungswasser u. Ä. gehört nicht auf die Einkaufsliste */
export function isPantryBasic(name: string): boolean {
  return /^wasser\b/i.test(name.trim());
}
