import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { parseRecipeCollection } from "../lib/markdown";
import { CATALOG_BOOKS, DISH_PHOTOS, dishPhoto } from "../lib/medien";

describe("Beispielbilder und Kochbücher", () => {
  const recipes = parseRecipeCollection(readFileSync(join(__dirname, "..", "data", "rezeptsammlung.md"), "utf8"));

  it("hat für jedes Rezept ein lokales Beispielbild mit Quelle", () => {
    expect(DISH_PHOTOS).toHaveLength(recipes.length);
    for (const recipe of recipes) {
      const photo = DISH_PHOTOS.find((d) => d.title === recipe.title);
      expect(photo?.src?.startsWith("/images/rezepte/")).toBe(true);
      expect(photo?.author && photo.license && photo.sourceUrl).toBeTruthy();
      expect(existsSync(join(__dirname, "..", "public", photo!.src!))).toBe(true);
    }
    expect(dishPhoto("Shakshuka mit Kichererbsen & Kokosmilch")?.src).toBe("/images/rezepte/shakshuka.jpg");
  });

  it("erfindet keine ISBN und lässt unsichere Bücher leer", () => {
    expect(CATALOG_BOOKS).toHaveLength(15);
    for (const book of CATALOG_BOOKS) {
      expect(book.coverUrl?.startsWith("/images/kochbuecher/")).toBe(true);
      expect(book.coverQuelle).toBeTruthy();
      expect(existsSync(join(__dirname, "..", "public", book.coverUrl!))).toBe(true);
      if (book.isbn) {
        expect(book.isbn).toMatch(/^978-\d-\d{2,7}-\d{1,7}-\d$/);
        expect(book.quelle).toBeTruthy();
        expect(book.hinweis).toBeNull();
      } else {
        expect(book.hinweis).toBeTruthy();
      }
    }
    expect(CATALOG_BOOKS.find((b) => b.title === "Ottolenghi Test Kitchen")?.isbn).toBeNull();
    expect(CATALOG_BOOKS.find((b) => b.title === "Jerusalem")?.isbn).toBe("978-3-8310-2333-2");
  });
});
