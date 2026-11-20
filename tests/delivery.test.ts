import { describe, expect, it } from "vitest";
import { shopSearchTerm, shopSearchUrl } from "../lib/delivery";

describe("shopSearchTerm", () => {
  it.each([
    ["480 g Hähnchenschenkel (ohne Knochen/Haut)", "Hähnchenschenkel"],
    ["Hähnchenschenkel", "Hähnchenschenkel"],
    ["2 Zwiebeln", "Zwiebeln"],
    ["1,5 l Milch", "Milch"],
    ["1 TL Olivenöl", "Olivenöl"],
    ["2 EL Tomatenmark", "Tomatenmark"],
    ["½ Bund Petersilie", "Petersilie"],
    ["3 Zehen Knoblauch, fein gehackt", "Knoblauch"],
    ["ca. 200 g Feta", "Feta"],
    ["2-3 Möhren", "Möhren"],
    ["4 Große Tortillas", "Tortillas"],
    ["1 Dose Kokosmilch", "Kokosmilch"],
    ["Salz nach Geschmack", "Salz"],
    ["150 ml Frank's Hot Sauce", "Frank's Hot Sauce"],
    ["Klopapier", "Klopapier"],
    ["Eier; Größe M", "Eier"],
    ["1 Stück Ingwer [frisch]", "Ingwer"],
    ["2 x Joghurt", "Joghurt"],
    ["1 Bund Frischer Koriander", "Koriander"],
    ["0,5 Kopf Eisbergsalat oder Butterlatich", "Eisbergsalat"],
    ["Butter / Margarine", "Butter"],
    ["1 Packung Spaghetti", "Spaghetti"],
  ])("%s → %s", (input, expected) => {
    expect(shopSearchTerm(input)).toBe(expected);
  });

  it("fällt auf den Originaltext zurück, wenn nichts übrig bleibt", () => {
    expect(shopSearchTerm("500 g")).toBe("500 g");
  });
});

describe("shopSearchUrl", () => {
  it("baut die Suchadressen der Shops", () => {
    expect(shopSearchUrl("rewe", "2 EL Crème fraîche")).toBe("https://www.rewe.de/shop/productList?search=Cr%C3%A8me%20fra%C3%AEche");
    expect(shopSearchUrl("knuspr", "1 l Milch")).toBe("https://www.knuspr.de/suche?q=Milch");
  });
});
