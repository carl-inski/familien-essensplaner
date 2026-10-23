import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { anchorFor, collectionToMarkdown, parseRecipeCollection, parseTimeMinutes } from "../lib/markdown";

const source = readFileSync(join(__dirname, "..", "data", "rezeptsammlung.md"), "utf8");

describe("Markdown-Import", () => {
  const recipes = parseRecipeCollection(source);

  it("liest alle 19 Rezepte", () => {
    expect(recipes).toHaveLength(19);
    expect(recipes[0].title).toBe("Spinatquiche mit Feta");
    expect(recipes[18].title).toBe("Honighähnchen");
  });

  it("übernimmt Metadaten, Gruppen, Schritte, Tipp und Nährwerte", () => {
    const teriyaki = recipes.find((r) => r.title === "Teriyaki Hähnchen")!;
    expect(teriyaki.categories).toEqual(["Geflügel", "Asiatisch"]);
    expect(teriyaki.diet).toBe("fleisch");
    expect(teriyaki.servings).toBe(4);
    expect(teriyaki.ingredients).toHaveLength(12);
    expect(teriyaki.ingredients[5]).toMatchObject({ group_name: "Teriyaki-Sauce", name: "Sojasauce", amount: 75, unit: "ml" });
    expect(teriyaki.steps).toHaveLength(9);

    const honig = recipes.find((r) => r.title === "Honighähnchen")!;
    expect(honig.subtitle).toBe("Süße rote Zwiebeln, Oregano, Orangen, Feta & Pistazien");
    expect(honig.tip).toBe("Dazu passen Couscous oder ein einfacher Salat.");
    expect(honig.nutrition?.kcal).toBe("442");
    expect(honig.nutrition?.Eiweiß).toBe("42 g");
    expect(honig.time_min).toBe(66);

    const riegel = recipes.find((r) => r.title.startsWith("Fitness-Reisriegel"))!;
    expect(riegel.servings).toBeNull();
    expect(riegel.servings_text).toMatch(/^2 Dosen/);
    expect(riegel.ingredients.find((i) => i.name === "Wasser")).toMatchObject({ amount: 1.2, unit: "l", amount_text: "1–1,2 l" });

    const pizza = recipes.find((r) => r.title.startsWith("Pizza"))!;
    expect(pizza.servings_text).toBe("4 (2 Pizzen)");
    expect(pizza.ingredients.find((i) => i.name === "Trockenhefe")).toMatchObject({ amount: 7, unit: "g" });
  });

  it("leitet die Ernährungsform ab", () => {
    const diet = Object.fromEntries(recipes.map((r) => [r.title, r.diet]));
    expect(diet["Spinatquiche mit Feta"]).toBe("vegetarisch");
    expect(diet["Pasta Räucherlachs"]).toBe("fisch");
    expect(diet["Pizza (Rucola & Schinken)"]).toBe("fleisch");
    expect(diet["Kartoffelknödel mit Schweinegeschnetzeltem"]).toBe("fleisch");
    expect(diet["Ananascurry (nach Leon: Fast Vegetarian)"]).toBe("vegetarisch");
  });

  it("Round-Trip: Import → Export → Import ergibt identische Daten", () => {
    const exported = collectionToMarkdown(recipes);
    const reimported = parseRecipeCollection(exported);
    expect(reimported).toEqual(recipes);
    // und ein zweiter Export ist byte-identisch zum ersten
    expect(collectionToMarkdown(reimported)).toBe(exported);
  });

  it("baut Anker wie im Inhaltsverzeichnis", () => {
    expect(anchorFor("Shakshuka mit Kichererbsen & Kokosmilch")).toBe("shakshuka-mit-kichererbsen--kokosmilch");
    expect(anchorFor("Fitness-Reisriegel (PB&J & Banane-Schoko)")).toBe("fitness-reisriegel-pbj--banane-schoko");
    expect(source).toContain(`(#${anchorFor("Pizza (Rucola & Schinken)")})`);
  });

  it("summiert Zeitangaben", () => {
    expect(parseTimeMinutes("Backzeit: 35–40 Min bei 180°C")).toBe(40);
    expect(parseTimeMinutes("Kochzeit: ca. 25 Min. + 2–3 Std. Kühlen")).toBe(205);
    expect(parseTimeMinutes(null)).toBeNull();
  });
});
