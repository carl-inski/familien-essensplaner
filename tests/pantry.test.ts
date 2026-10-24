import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { parseRecipeCollection } from "../lib/markdown";
import { isValidEntry, pantryEntriesFor, pantryEntriesFromInput, pantryEntriesToAdd, pantryKey, withoutPantry } from "../lib/pantry";
import { buildShoppingList } from "../lib/planning";
import { parseAmount } from "../lib/quantity";
import type { Ingredient, MealPlanEntry, Member, Recipe } from "../lib/types";

const recipes = parseRecipeCollection(readFileSync(join(__dirname, "..", "data", "rezeptsammlung.md"), "utf8"));
// Zutaten aus der Sammlung plus echte Namen aus der Datenbank, die dort anders geschrieben sind
const NAMES = [
  ...new Set([
    ...recipes.flatMap((r) => r.ingredients.map((i) => i.name)),
    "Hähnchenober- und -unterschenkel (mit Haut und Knochen)",
    "Rinder- oder Gemüsebrühe",
    "Garnelen (gekocht) oder Hähnchenbrust",
    "Saure Sahne oder Schmand, Käse (gerieben), Koriander oder Petersilie",
    "Reis, Brot oder Tortilla-Chips zum Servieren",
    "Schweinegeschnetzeltes / Schweinerücken",
    "Meersalz, schwarzer Pfeffer",
    "Olivenöl, Salz, Pfeffer",
    "Pfeffer, frisch gemahlen",
    "Kokosnussöl oder Olivenöl",
    "Sake oder trockener Sherry",
  ]),
];

describe("Vorrat: Rundlauf über alle echten Zutaten", () => {
  it.each(NAMES)("%s", (name) => {
    const entries = pantryEntriesToAdd(name);
    expect(entries.length).toBeGreaterThan(0);
    for (const e of entries) expect(isValidEntry(e)).toBe(true);
    const pantry = new Set(entries);
    // Häuschen antippen → steht nicht mehr auf der Liste
    expect(withoutPantry(name, pantry)).toBeNull();
    // „wieder einkaufen“ findet alle Einträge, die die Zeile abdecken …
    const covering = pantryEntriesFor(name, pantry);
    expect(new Set(covering)).toEqual(pantry);
    // … und danach steht die Zutat wieder vollständig da
    const rest = new Set([...pantry].filter((e) => !covering.includes(e)));
    expect(withoutPantry(name, rest)).toBe(name);
  });
});

describe("Vorrat: Einzelfälle", () => {
  const p = (...e: string[]) => new Set(e);

  it("zerlegt keine Wörter mit Ergänzungsstrich", () => {
    expect(pantryEntriesToAdd("Hähnchenober- und -unterschenkel (mit Haut und Knochen)")).toEqual(["hähnchenober- und -unterschenkel"]);
    expect(pantryEntriesToAdd("Rinder- oder Gemüsebrühe")).toEqual(["rinder- oder gemüsebrühe"]);
  });

  it("zerlegt echte Sammelzeilen", () => {
    expect(pantryEntriesToAdd("Salz, Pfeffer")).toEqual(["salz", "pfeffer"]);
    expect(pantryEntriesToAdd("Salz und Pfeffer")).toEqual(["salz", "pfeffer"]);
    expect(pantryEntriesToAdd("Knoblauch, Oregano, Olivenöl")).toEqual(["knoblauch", "oregano", "olivenöl"]);
  });

  it("lässt Zubereitungshinweise und Klammern weg", () => {
    expect(pantryKey("Pfeffer, frisch gemahlen")).toBe("pfeffer");
    expect(pantryKey("Olivenöl (extra vergine)")).toBe("olivenöl");
  });

  it("kürzt Sammelzeilen um den Vorrat", () => {
    expect(withoutPantry("Muskat, Salz, Pfeffer", p("salz", "pfeffer"))).toBe("Muskat");
    expect(withoutPantry("Olivenöl, Salz, Pfeffer", p("salz", "pfeffer"))).toBe("Olivenöl");
    expect(withoutPantry("Meersalz, schwarzer Pfeffer", p("salz", "pfeffer"))).toBe("Meersalz");
  });

  it("erkennt Varianten derselben Zutat", () => {
    expect(withoutPantry("schwarzer Pfeffer", p("pfeffer"))).toBeNull();
    expect(withoutPantry("Zwiebeln", p("zwiebel"))).toBeNull();
    expect(withoutPantry("Eier", p("ei"))).toBeNull();
    expect(withoutPantry("Olivenöl (extra vergine)", p("olivenöl"))).toBeNull();
    expect(withoutPantry("Kokosnussöl oder Olivenöl", p("olivenöl"))).toBeNull();
  });

  it("verwechselt keine ähnlichen Zutaten", () => {
    expect(withoutPantry("Meersalz", p("salz"))).toBe("Meersalz");
    expect(withoutPantry("Salzreduzierte Sojasauce", p("salz"))).toBe("Salzreduzierte Sojasauce");
    expect(withoutPantry("Hähnchenbrust", p("hähnchenober- und -unterschenkel"))).toBe("Hähnchenbrust");
    expect(withoutPantry("Knoblauchpulver", p("knoblauch"))).toBe("Knoblauchpulver");
    expect(withoutPantry("Paprika (rot)", p("paprikapulver"))).toBe("Paprika (rot)");
  });

  it("ignoriert Bruchstücke aus der alten Version", () => {
    expect(isValidEntry("-unterschenkel")).toBe(false);
    expect(isValidEntry("hähnchenober-")).toBe(false);
    expect(withoutPantry("Hähnchenober- und -unterschenkel (mit Haut und Knochen)", p("hähnchenober-", "-unterschenkel"))).not.toBeNull();
  });

  it("nimmt Freitext im Haushalt kommagetrennt", () => {
    expect(pantryEntriesFromInput("Olivenöl, Zucker; Mehl")).toEqual(["olivenöl", "zucker", "mehl"]);
    expect(pantryEntriesFromInput("Rinder- oder Gemüsebrühe")).toEqual(["rinder- oder gemüsebrühe"]);
  });
});

describe("Vorrat in der Einkaufsliste", () => {
  const ing = (name: string, amount_text: string | null, position = 0): Ingredient => ({ position, group_name: null, name, amount_text, ...parseAmount(amount_text) });
  const member = (id: string): Member => ({ id, household_id: "h", name: id, email: null, user_id: null, role: "member", default_week: {}, position: 0 });
  const entry = (id: string, recipe_id: string): MealPlanEntry => ({ id, household_id: "h", date: "2026-10-26", meal: "abend", recipe_id, leftover_of: null, cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null });
  const r = { id: "r", title: "Brathähnchen", servings: 4, diet: "fleisch", tags: [], categories: [], cookbook_id: null, ep_recipe_ingredients: [ing("Hähnchenober- und -unterschenkel (mit Haut und Knochen)", "1,2 kg"), ing("Süßkartoffeln", "4"), ing("Salz, Pfeffer", null)] } as unknown as Recipe;

  it("blendet die ganze Zutat aus und zeigt sie als einen Eintrag", () => {
    const entries = pantryEntriesToAdd("Hähnchenober- und -unterschenkel (mit Haut und Knochen)");
    const pantry = new Set(["salz", "pfeffer", ...entries]);
    const list = buildShoppingList([entry("1", "r")], new Map([["r", r]]), ["a", "b", "c", "d"].map(member), [], pantry);
    expect(list.filter((i) => !i.pantry).map((i) => i.name)).toEqual(["Süßkartoffeln"]);
    const chips = [...new Set(list.filter((i) => i.pantry).flatMap((i) => pantryEntriesFor(i.name, pantry)))].sort();
    expect(chips).toEqual(["hähnchenober- und -unterschenkel", "pfeffer", "salz"]);
  });
});
