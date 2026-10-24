import { describe, expect, it } from "vitest";
import { extractToDraft, RecipeExtractSchema } from "../lib/ai/schemas";
import { mockRecipeExtract } from "../lib/ai/mocks";
import { splitIngredientLine } from "../lib/quantity";
import { cleanText, isoDurationMinutes, needsTranslation, pageLanguage, pageText, recipeFromHtml } from "../lib/recipe-jsonld";

const page = (ld: unknown) => `<html><head><script type="application/ld+json">${JSON.stringify(ld)}</script></head><body>…</body></html>`;

describe("splitIngredientLine", () => {
  it.each([
    ["200 g Mehl", "200 g", "Mehl"],
    ["2 große Zwiebeln, gewürfelt", "2", "große Zwiebeln, gewürfelt"],
    ["1 Prise Salz", "1 Prise", "Salz"],
    ["7g Trockenhefe", "7 g", "Trockenhefe"],
    ["2–3 EL Olivenöl", "2–3 EL", "Olivenöl"],
    ["½ Bund Petersilie", "½ Bund", "Petersilie"],
    ["1 Pck. Backpulver", "1 Pck.", "Backpulver"],
    ["ca. 500 ml Brühe", "500 ml", "Brühe"],
  ])("%s", (line, amount, name) => {
    expect(splitIngredientLine(line)).toEqual({ amount_text: amount, name });
  });

  it("lässt Zeilen ohne Menge als Namen stehen", () => {
    expect(splitIngredientLine("Salz und Pfeffer")).toEqual({ amount_text: null, name: "Salz und Pfeffer" });
  });
});

describe("isoDurationMinutes", () => {
  it("liest ISO-8601-Dauern", () => {
    expect(isoDurationMinutes("PT45M")).toBe(45);
    expect(isoDurationMinutes("PT1H15M")).toBe(75);
    expect(isoDurationMinutes("P0DT2H")).toBe(120);
    expect(isoDurationMinutes("PT")).toBeNull();
    expect(isoDurationMinutes("45 Minuten")).toBeNull();
  });
});

describe("recipeFromHtml", () => {
  it("liest die eigene /r/<slug>-Seite (Bring!-Format)", () => {
    const d = recipeFromHtml(
      page({
        "@context": "https://schema.org",
        "@type": "Recipe",
        name: "Chili con Carne",
        author: { "@type": "Organization", name: "Familien-Essensplaner" },
        recipeYield: "4",
        recipeIngredient: ["500 g Rinderhack", "2 Dosen Kidneybohnen", "1 TL Kreuzkümmel"],
        recipeInstructions: [{ "@type": "HowToStep", text: "Hack anbraten." }, { "@type": "HowToStep", text: "Bohnen zugeben." }],
      }),
      "https://example.org/r/abc",
    )!;
    expect(d.title).toBe("Chili con Carne");
    expect(d.servings).toBe(4);
    expect(d.diet).toBe("fleisch");
    expect(d.ingredients[1]).toMatchObject({ name: "Kidneybohnen", amount_text: "2 Dosen", amount: 2, unit: "Dose" });
    expect(d.steps).toEqual(["Hack anbraten.", "Bohnen zugeben."]);
    expect(d.source).toBe("https://example.org/r/abc");
  });

  it("findet das Rezept im @graph und liest Zeiten, Abschnitte, Nährwerte und Bild", () => {
    const d = recipeFromHtml(
      page({
        "@context": "https://schema.org",
        "@graph": [
          { "@type": "WebPage", name: "Blog" },
          {
            "@type": ["Recipe", "Thing"],
            name: "Spinat-Quiche &amp; Feta",
            description: "Schnell und knusprig.",
            image: [{ "@type": "ImageObject", url: "https://cdn.example.org/quiche.jpg" }],
            recipeYield: ["4", "4 Stücke"],
            prepTime: "PT20M",
            cookTime: "PT40M",
            recipeCategory: "Hauptgericht",
            keywords: "Quiche, Spinat",
            nutrition: { "@type": "NutritionInformation", calories: "520 kcal", proteinContent: "21.5 g" },
            recipeIngredient: ["1 Rolle Blätterteig", "300 g Spinat", "200 g Feta"],
            recipeInstructions: [
              { "@type": "HowToSection", name: "Teig", itemListElement: [{ "@type": "HowToStep", text: "<p>Form auslegen.</p>" }] },
              { "@type": "HowToSection", name: "Füllung", itemListElement: [{ "@type": "HowToStep", text: "Spinat und Feta mischen." }] },
            ],
          },
        ],
      }),
      null,
    )!;
    expect(d.title).toBe("Spinat-Quiche & Feta");
    expect(d.subtitle).toBe("Schnell und knusprig.");
    expect(d.time_min).toBe(60);
    expect(d.time_text).toBe("Vorbereitung 20 Min. / Garzeit 40 Min.");
    expect(d.steps).toEqual(["Form auslegen.", "Spinat und Feta mischen."]);
    expect(d.nutrition).toMatchObject({ kcal: "520", Eiweiß: "21,5 g" });
    expect(d.image_url).toBe("https://cdn.example.org/quiche.jpg");
    expect(d.diet).toBe("vegetarisch");
    expect(d.tags).toContain("spinat");
  });

  it("teilt Anleitungen als Textblock in Schritte", () => {
    const d = recipeFromHtml(page({ "@type": "Recipe", name: "Suppe", recipeIngredient: ["1 l Brühe"], recipeInstructions: "1. Aufkochen. 2. Würzen." }), null)!;
    expect(d.steps).toEqual(["Aufkochen.", "Würzen."]);
  });

  it("überspringt kaputtes JSON und Seiten ohne Rezept", () => {
    expect(recipeFromHtml(`<script type="application/ld+json">{kaputt</script>`, null)).toBeNull();
    expect(recipeFromHtml(page({ "@type": "Article", name: "News" }), null)).toBeNull();
  });
});

describe("pageText und cleanText", () => {
  it("entfernt Skripte, Navigation und Tags", () => {
    const t = pageText("<nav>Menü</nav><script>alert(1)</script><h1>Pfannkuchen</h1><p>200 g Mehl</p>");
    expect(t).toContain("Pfannkuchen");
    expect(t).toContain("200 g Mehl");
    expect(t).not.toContain("alert");
    expect(t).not.toContain("Menü");
  });
  it("löst Entities auf", () => {
    expect(cleanText("Fr&uuml;hst&uuml;ck &#8211; schnell")).toBe("Frühstück – schnell");
  });
});

describe("extractToDraft", () => {
  it("wandelt die Mock-Antwort in einen gültigen Entwurf", () => {
    const x = RecipeExtractSchema.parse(JSON.parse(mockRecipeExtract()));
    const d = extractToDraft(x, "https://example.org");
    expect(d.ingredients[0]).toMatchObject({ name: "rote Linsen", amount: 250, unit: "g" });
    expect(d.cookbook).toEqual({ title: "Ottolenghi Simple", page: 42 });
    expect(d.tags).toEqual(["suppe"]);
  });

  it("korrigiert eine vegetarische Einordnung bei Fleischzutaten", () => {
    const x = RecipeExtractSchema.parse({ ...JSON.parse(mockRecipeExtract()), ingredients: [{ group: null, amount: "200 g", name: "Speck" }] });
    expect(extractToDraft(x, null).diet).toBe("fleisch");
  });
});

describe("needsTranslation", () => {
  const base = recipeFromHtml(page({ "@type": "Recipe", name: "Ragu", recipeIngredient: ["3 tbsp olive oil", "400g sausages"] }), null)!;
  it("übersetzt bei fremder Seitensprache oder englischen Einheiten", () => {
    expect(needsTranslation(base, "en-gb")).toBe(true);
    expect(needsTranslation(base, null)).toBe(true);
    expect(needsTranslation(base, "de")).toBe(false);
  });
  it("lässt deutsche Rezepte ohne Sprachangabe in Ruhe", () => {
    const de = recipeFromHtml(page({ "@type": "Recipe", name: "Suppe", recipeIngredient: ["1 l Brühe", "2 EL Öl"] }), null)!;
    expect(needsTranslation(de, null)).toBe(false);
    expect(pageLanguage('<html class="x" lang="de-DE">')).toBe("de-de");
  });
});
