import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { checkBearer, importRecipes, normalizeTitle, parseModus, parsePayload, recipeSummaries, type RecipeStore } from "../lib/api/recipes";
import type { Cookbook, Recipe } from "../lib/types";

const SAMMLUNG = readFileSync(join(__dirname, "..", "data", "rezeptsammlung.md"), "utf8");
const TOKEN = "a".repeat(64);

const EIN_REZEPT = `## Ofenlachs mit Brokkoli, Kartoffeln & Feta-Joghurt

**Quelle:** Küchenchef
**Kochbuch:** ONE, S. 112
**Kategorie:** Fisch / Blech
**Zeit:** ca. 45 Min.
**Portionen:** 2

### Zutaten

| Zutat | Menge |
|---|---|
| **Blech** | |
| Lachsfilets | 2 |
| Kartoffeln (festkochend) | 750 g |
| **Feta-Joghurt** | |
| Joghurt | 225 g |
| Feta | 75 g |

### Zubereitung

1. Ofen auf 200 °C vorheizen.
2. Alles aufs Blech.

**Tipp:** Gefrorener Lachs geht auch.

**Nährwerte pro Portion:** 520 kcal | Eiweiß 38 g
`;

// ---------------------------------------------------------------------------

describe("checkBearer", () => {
  it("prüft fehlenden, falschen und richtigen Token", () => {
    expect(checkBearer(null, TOKEN)).toBe("unauthorized");
    expect(checkBearer("Bearer falsch", TOKEN)).toBe("unauthorized");
    expect(checkBearer(`Bearer ${"b".repeat(64)}`, TOKEN)).toBe("unauthorized");
    expect(checkBearer(`Basic ${TOKEN}`, TOKEN)).toBe("unauthorized");
    expect(checkBearer(`Bearer ${TOKEN}`, TOKEN)).toBe("ok");
    expect(checkBearer(`bearer ${TOKEN} `, TOKEN)).toBe("ok");
  });
  it("meldet „nicht eingerichtet“ ohne Env", () => {
    expect(checkBearer(`Bearer ${TOKEN}`, undefined)).toBe("not-configured");
    expect(checkBearer(`Bearer ${TOKEN}`, "  ")).toBe("not-configured");
  });
});

describe("normalizeTitle", () => {
  it("behandelt & und „und“ gleich", () => {
    expect(normalizeTitle("Ofenlachs mit Brokkoli, Kartoffeln & Feta-Joghurt")).toBe(normalizeTitle("Ofenlachs mit Brokkoli, Kartoffeln und Feta-Joghurt"));
  });
  it("ignoriert Groß/klein, Satzzeichen und Leerzeichen, behält Klammerzusätze", () => {
    expect(normalizeTitle("  Chili   con CARNE! ")).toBe("chili con carne");
    expect(normalizeTitle("Pizza (Rucola & Schinken)")).toBe("pizza rucola und schinken");
    expect(normalizeTitle("Pizza (Rucola & Schinken)")).not.toBe(normalizeTitle("Pizza"));
  });
});

describe("parsePayload: Markdown", () => {
  it("liest ein Rezept mit Gruppen, Kochbuch, Tipp und Nährwerten", () => {
    const { drafts, errors } = parsePayload("text/markdown", EIN_REZEPT);
    expect(errors).toEqual([]);
    expect(drafts).toHaveLength(1);
    const d = drafts[0];
    expect(d.cookbook).toEqual({ title: "ONE", page: 112 });
    expect(d.servings).toBe(2);
    expect(d.diet).toBe("fisch");
    expect(d.ingredients.map((i) => i.group_name)).toEqual(["Blech", "Blech", "Feta-Joghurt", "Feta-Joghurt"]);
    expect(d.ingredients[1]).toMatchObject({ name: "Kartoffeln (festkochend)", amount: 750, unit: "g" });
    expect(d.tip).toBe("Gefrorener Lachs geht auch.");
    expect(d.nutrition).toMatchObject({ kcal: "520", Eiweiß: "38 g" });
  });

  it("liest zwei Rezepte und überspringt das Inhaltsverzeichnis", () => {
    const md = `# Sammlung\n\n## Inhalt\n\n1. [A](#a)\n2. [B](#b)\n\n---\n\n${EIN_REZEPT}\n---\n\n${EIN_REZEPT.replace("Ofenlachs mit", "Zweiter Lachs mit")}`;
    const { drafts } = parsePayload("text/markdown; charset=utf-8", md);
    expect(drafts.map((d) => d.title)).toEqual(["Ofenlachs mit Brokkoli, Kartoffeln & Feta-Joghurt", "Zweiter Lachs mit Brokkoli, Kartoffeln & Feta-Joghurt"]);
  });

  it("liest die ganze Rezeptsammlung mit 20 Rezepten", () => {
    const { drafts, errors } = parsePayload("text/markdown", SAMMLUNG);
    expect(errors).toEqual([]);
    expect(drafts).toHaveLength(20);
    const riegel = drafts.find((d) => d.title.startsWith("Fitness-Reisriegel"))!;
    expect(riegel.servings).toBeNull();
    expect(riegel.servings_text).toMatch(/^2 Dosen/);
    expect(riegel.ingredients.find((i) => i.name === "Wasser")).toMatchObject({ amount: 1.2, unit: "l" });
    const ofenlachs = drafts.find((d) => d.title.startsWith("Ofenlachs"))!;
    expect(ofenlachs.ingredients.filter((i) => i.group_name === "Feta-Joghurt")).toHaveLength(4);
    // Die Sammlung nennt Bücher als Quelle (Kochbuch mit Seite prüft der Einzeltest)
    expect(drafts.find((d) => d.title.startsWith("One-Pot Räucherlachs"))?.source).toMatch(/Jamie Oliver/);
    expect(drafts.filter((d) => d.tip).length).toBeGreaterThan(5);
    expect(drafts.find((d) => d.title === "Honighähnchen")?.nutrition?.kcal).toBe("442");
  });

  it("lehnt leere Texte und Rezepte ohne Zutaten und Kochbuch ab", () => {
    expect(parsePayload("text/markdown", "hallo").errors[0].fehler).toMatch(/Kein Rezept/);
    const ohne = `## Nur Titel\n\n### Zubereitung\n\n1. Kochen.\n`;
    expect(parsePayload("text/markdown", ohne).errors[0]).toMatchObject({ titel: "Nur Titel" });
  });
});

describe("parsePayload: JSON", () => {
  const rezept = {
    titel: "Ofenlachs mit Brokkoli, Kartoffeln & Feta-Joghurt",
    quelle: "Küchenchef",
    kochbuch: { titel: "ONE", seite: 112 },
    kategorien: ["Fisch", "Blech"],
    zeit: "ca. 45 Min.",
    portionen: 2,
    portionen_text: null,
    zutaten: [{ gruppe: "Blech", name: "Kartoffeln (festkochend)", menge: "750 g" }],
    schritte: ["Ofen auf 200 °C …"],
    tipp: "…",
    naehrwerte: "ca. 520 kcal | 38 g Eiweiß",
    bild_url: null,
  };

  it("wandelt das Beispiel aus dem Auftrag", () => {
    const { drafts, errors } = parsePayload("application/json", JSON.stringify({ rezepte: [rezept] }));
    expect(errors).toEqual([]);
    const d = drafts[0];
    expect(d).toMatchObject({ title: rezept.titel, source: "Küchenchef", cookbook: { title: "ONE", page: 112 }, servings: 2, servings_text: "2", time_min: 45, diet: "fisch", tags: ["fisch", "blech"] });
    expect(d.ingredients[0]).toMatchObject({ group_name: "Blech", amount: 750, unit: "g", amount_text: "750 g" });
    expect(d.nutrition?.text).toBe("ca. 520 kcal | 38 g Eiweiß");
  });

  it("prüft Pflichtfelder einzeln, ohne den Stapel abzubrechen", () => {
    const { drafts, errors } = parsePayload("application/json", JSON.stringify({ rezepte: [rezept, { titel: "Ohne Zutaten" }, { zutaten: [] }] }));
    expect(drafts).toHaveLength(1);
    expect(errors.map((e) => e.titel)).toEqual(["Ohne Zutaten", "Rezept 3"]);
  });

  it("ignoriert household_id im Body und nimmt nur http(s)-Bilder", () => {
    const evil = { ...rezept, household_id: "00000000-0000-0000-0000-000000000000", bild_url: "javascript:alert(1)" };
    const d = parsePayload("application/json", JSON.stringify({ rezepte: [evil] })).drafts[0];
    expect(d).not.toHaveProperty("household_id");
    expect(d.image_url).toBeNull();
    expect(parsePayload("application/json", JSON.stringify({ rezepte: [{ ...rezept, bild_url: "https://x.de/a.jpg" }] })).drafts[0].image_url).toBe("https://x.de/a.jpg");
  });

  it("explizite Ernährung schlägt die Ableitung", () => {
    const d = parsePayload("application/json", JSON.stringify({ rezepte: [{ ...rezept, ernaehrung: "vegetarisch" }] })).drafts[0];
    expect(d.diet).toBe("vegetarisch");
  });

  it("meldet kaputtes JSON und falsche Hülle", () => {
    expect(parsePayload("application/json", "{kaputt").errors[0].fehler).toBe("Ungültiges JSON");
    expect(parsePayload("application/json", JSON.stringify([rezept])).errors[0].fehler).toMatch(/rezepte/);
  });
});

// ---------------------------------------------------------------------------
// Duplikat-Modi mit nachgebildetem Speicher
// ---------------------------------------------------------------------------

function fakeStore(recipes: Partial<Recipe>[] = [], cookbooks: Partial<Cookbook>[] = []) {
  const saved: Parameters<RecipeStore["save"]>[0][] = [];
  let n = 0;
  const store: RecipeStore = {
    snapshot: async () => ({ recipes: recipes as Recipe[], cookbooks: cookbooks as Cookbook[] }),
    save: async (input) => {
      if (input.recipe.title === "Kaputt") throw new Error("DB-Fehler");
      saved.push(input);
      return input.existingId ?? `neu-${++n}`;
    },
  };
  return { store, saved };
}

const vorhanden = [{ id: "r1", title: "Ofenlachs mit Brokkoli, Kartoffeln und Feta-Joghurt", servings: 2, updated_at: "2026-10-24T10:00:00Z", cookbook_id: "b1" }];
const regal = [{ id: "b1", title: "ONE", authors: ["Jamie Oliver"] }];

describe("importRecipes", () => {
  it("Modus neu: Duplikat → 409 mit vorhandener id, nichts geschrieben", async () => {
    const { store, saved } = fakeStore(vorhanden, regal);
    const res = await importRecipes(store, parsePayload("text/markdown", EIN_REZEPT), "neu", false);
    expect(res.status).toBe(409);
    expect(res.body.ergebnisse[0]).toMatchObject({ status: "duplikat", id: "r1", url: "/rezepte/r1" });
    expect(saved).toHaveLength(0);
  });

  it("Modus ueberspringen: Duplikat still aus, Neues angelegt", async () => {
    const { store, saved } = fakeStore(vorhanden, regal);
    const md = `${EIN_REZEPT}\n---\n\n${EIN_REZEPT.replace("Ofenlachs mit", "Neuer Lachs mit")}`;
    const res = await importRecipes(store, parsePayload("text/markdown", md), "ueberspringen", false);
    expect(res.status).toBe(201);
    expect(res.body.ergebnisse.map((e) => e.status)).toEqual(["uebersprungen", "angelegt"]);
    expect(saved).toHaveLength(1);
    expect(saved[0].existingId).toBeNull();
  });

  it("Modus ueberschreiben: aktualisiert per id, Kochbuch bestätigt", async () => {
    const { store, saved } = fakeStore(vorhanden, regal);
    const res = await importRecipes(store, parsePayload("text/markdown", EIN_REZEPT), "ueberschreiben", false);
    expect(res.status).toBe(200);
    expect(res.body.ergebnisse[0]).toMatchObject({ status: "aktualisiert", id: "r1" });
    expect(saved[0]).toMatchObject({ existingId: "r1", createCookbook: null });
    expect(saved[0].recipe).toMatchObject({ cookbook_id: "b1", cookbook_page: 112, cookbook_link_confirmed: true });
    expect(saved[0].ingredients).toHaveLength(4);
    expect(saved[0].ingredients[0]).not.toHaveProperty("recipe_id");
  });

  it("unbekanntes Kochbuch wird unbestätigt angelegt", async () => {
    const { store, saved } = fakeStore([], []);
    await importRecipes(store, parsePayload("text/markdown", EIN_REZEPT), "neu", false);
    expect(saved[0]).toMatchObject({ createCookbook: "ONE" });
    expect(saved[0].recipe).toMatchObject({ cookbook_id: null, cookbook_link_confirmed: false });
  });

  it("ohne Kochbuch-Zeile nur ein unbestätigter Vorschlag", async () => {
    const { store, saved } = fakeStore([], [{ id: "b2", title: "ONE", authors: ["Jamie Oliver"] }]);
    const md = EIN_REZEPT.replace("**Kochbuch:** ONE, S. 112\n", "").replace("**Quelle:** Küchenchef", "**Quelle:** Jamie Oliver – ONE: Simple One-Pan Wonders");
    await importRecipes(store, parsePayload("text/markdown", md), "neu", false);
    expect(saved[0].recipe).toMatchObject({ cookbook_id: "b2", cookbook_link_confirmed: false });
  });

  it("dry_run schreibt nichts und zeigt die Entwürfe", async () => {
    const { store, saved } = fakeStore(vorhanden, regal);
    const res = await importRecipes(store, parsePayload("text/markdown", SAMMLUNG), "ueberschreiben", true);
    expect(saved).toHaveLength(0);
    expect(res.status).toBe(200);
    expect(res.body.dry_run).toBe(true);
    expect(res.body.ergebnisse).toHaveLength(20);
    const lachs = res.body.ergebnisse.find((e) => e.titel.startsWith("Ofenlachs"))!;
    expect(lachs).toMatchObject({ status: "aktualisiert", id: "r1" });
    expect(lachs.entwurf?.ingredients.length).toBeGreaterThan(0);
  });

  it("ein Fehler bricht den Stapel nicht ab", async () => {
    const { store, saved } = fakeStore();
    const md = `${EIN_REZEPT.replace(/^## .*$/m, "## Kaputt")}\n---\n\n${EIN_REZEPT}`;
    const res = await importRecipes(store, parsePayload("text/markdown", md), "neu", false);
    expect(res.body.ergebnisse.map((e) => e.status)).toEqual(["fehler", "angelegt"]);
    expect(res.status).toBe(201);
    expect(saved).toHaveLength(1);
  });

  it("doppelte Titel im selben Stapel werden nur einmal angelegt", async () => {
    const { store, saved } = fakeStore();
    const res = await importRecipes(store, parsePayload("text/markdown", `${EIN_REZEPT}\n---\n\n${EIN_REZEPT}`), "neu", false);
    expect(res.body.ergebnisse.map((e) => e.status)).toEqual(["angelegt", "fehler"]);
    expect(saved).toHaveLength(1);
  });

  it("nur Fehler → 422", async () => {
    const { store } = fakeStore();
    const res = await importRecipes(store, parsePayload("text/markdown", "kein rezept"), "neu", false);
    expect(res.status).toBe(422);
  });
});

describe("Kleinkram", () => {
  it("parseModus", () => {
    expect(parseModus(null)).toBe("neu");
    expect(parseModus("ueberschreiben")).toBe("ueberschreiben");
    expect(parseModus("loeschen")).toBeNull();
  });
  it("recipeSummaries", () => {
    expect(recipeSummaries(vorhanden as Recipe[], regal as Cookbook[])).toEqual([
      { id: "r1", title: vorhanden[0].title, updated_at: vorhanden[0].updated_at, servings: 2, cookbook_title: "ONE" },
    ]);
  });
});
